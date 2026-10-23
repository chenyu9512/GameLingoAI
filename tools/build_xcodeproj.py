#!/usr/bin/env python3
"""Generate an ordinary, self-contained Xcode project. No XcodeGen required."""
from __future__ import annotations
import hashlib
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = (ROOT / '.app_bundle_id').read_text().strip() if (ROOT / '.app_bundle_id').exists() else 'com.example.GameLingoAI'
DIRECT = os.environ.get('GAMELINGO_DIRECT_CAPTURE') == '1'
if DIRECT:
    BUNDLE_ID += '.direct'
DEST = ROOT / 'GameLingoAI.xcodeproj'
DEST.mkdir(exist_ok=True)

class Raw(str):
    pass

def oid(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()

def Q(v):
    if isinstance(v, Raw): return str(v)
    if isinstance(v, bool): return 'YES' if v else 'NO'
    if isinstance(v, int): return str(v)
    if isinstance(v, str):
        if v and all(c.isalnum() or c in '._/' for c in v) and v[0] not in '0123456789': return v
        return '"' + v.replace('\\','\\\\').replace('"','\\"') + '"'
    if isinstance(v, list):
        return '(\n' + ''.join('\t\t\t' + Q(x) + ',\n' for x in v) + '\t\t)'
    if isinstance(v, dict):
        return '{\n' + ''.join('\t\t\t' + Q(str(k)) + ' = ' + Q(val) + ';\n' for k,val in v.items()) + '\t\t}'
    raise TypeError(v)

objects={}

def obj(key, isa, **props):
    i=oid(key)
    objects[key]=dict(isa=isa,**props)
    return Raw(i)

src_app=(['ios/GameLingoAI/GameLingoAIApp.swift','ios/GameLingoAI/GameLingoStore.swift','ios/GameLingoAI/GameMenuCatalog.swift','ios/GameLingoAI/DirectHomeView.swift','ios/GameLingoAI/FloatingSubtitleController.swift','ios/GameLingoAI/DirectGameCapture.swift'] if DIRECT else ['ios/GameLingoAI/GameLingoAIApp.swift','ios/GameLingoAI/ContentView.swift','ios/GameLingoAI/SubtitleInbox.swift','ios/GameLingoAI/FloatingSubtitleController.swift'])
src_ext=['ios/BroadcastUpload/SampleHandler.swift']
src_shared=['ios/Shared/SubtitleMessage.swift','ios/Shared/BuildIdentity.swift']
plists=['ios/GameLingoAI/Info.plist','ios/BroadcastUpload/Info.plist','ios/GameLingoAI/InfoDirect.plist']
ents=['ios/GameLingoAI/GameLingoAI.entitlements','ios/BroadcastUpload/BroadcastUpload.entitlements']
assets='ios/GameLingoAI/Assets.xcassets'
files=src_app+src_ext+src_shared+plists+ents
refs={}
for p in files:
    typ='sourcecode.swift' if p.endswith('.swift') else ('text.plist.entitlements' if p.endswith('.entitlements') else 'text.plist.xml')
    refs[p]=obj('fileref:'+p,'PBXFileReference',lastKnownFileType=typ,path=Path(p).name,sourceTree='<group>')

refs[assets]=obj('fileref:'+assets,'PBXFileReference',lastKnownFileType='folder.assetcatalog',path='Assets.xcassets',sourceTree='<group>')

app_product=obj('prod:app','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='GameLingoAI.app',sourceTree='BUILT_PRODUCTS_DIR')
ext_product=obj('prod:extension','PBXFileReference',explicitFileType='wrapper.app-extension',includeInIndex=0,path='BroadcastUpload.appex',sourceTree='BUILT_PRODUCTS_DIR')

app_src=[obj('build:'+p+':app','PBXBuildFile',fileRef=refs[p]) for p in src_app+([] if DIRECT else src_shared)]
ext_src=[obj('build:'+p+':ext','PBXBuildFile',fileRef=refs[p]) for p in src_ext+src_shared]
ext_embed=obj('build:extension:embed','PBXBuildFile',fileRef=ext_product,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})

app_group=obj('group:app','PBXGroup',children=[refs[p] for p in src_app+plists[:1]+plists[2:]+ents[:1]]+[refs[assets]],path='GameLingoAI',sourceTree='<group>')
ext_group=obj('group:extension','PBXGroup',children=[refs[p] for p in src_ext+plists[1:2]+ents[1:]],path='BroadcastUpload',sourceTree='<group>')
shared_group=obj('group:shared','PBXGroup',children=[refs[p] for p in src_shared],path='Shared',sourceTree='<group>')
ios_group=obj('group:ios','PBXGroup',children=[app_group,ext_group,shared_group],path='ios',sourceTree='<group>')
prod_group=obj('group:products','PBXGroup',children=[app_product,ext_product],name='Products',sourceTree='<group>')
root_group=obj('group:main','PBXGroup',children=[ios_group,prod_group],sourceTree='<group>')

sources_app=obj('phase:sources:app','PBXSourcesBuildPhase',buildActionMask=2147483647,files=app_src,runOnlyForDeploymentPostprocessing=0)
sources_ext=obj('phase:sources:ext','PBXSourcesBuildPhase',buildActionMask=2147483647,files=ext_src,runOnlyForDeploymentPostprocessing=0)
frameworks_app=obj('phase:frameworks:app','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
frameworks_ext=obj('phase:frameworks:ext','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
app_assets=obj('build:app:assets','PBXBuildFile',fileRef=refs[assets])
resources_app=obj('phase:resources:app','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[app_assets],runOnlyForDeploymentPostprocessing=0)
resources_ext=obj('phase:resources:ext','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
embed_phase=obj('phase:embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[ext_embed],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)

common={
 'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES',
 'SWIFT_VERSION':'5.9','IPHONEOS_DEPLOYMENT_TARGET':'27.0' if DIRECT else '26.0',
 'SDKROOT':'iphoneos','CODE_SIGN_STYLE':'Automatic',
 'TARGETED_DEVICE_FAMILY':'1,2', 'SUPPORTS_MACCATALYST':'NO',
 'MARKETING_VERSION':'3.1.0' if DIRECT else '2.0.0','CURRENT_PROJECT_VERSION':'5' if DIRECT else '1',
 'GENERATE_INFOPLIST_FILE':'NO', 'SWIFT_EMIT_LOC_STRINGS':'YES',
 'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS':'NO',
}
app_build={**common, 'PRODUCT_BUNDLE_IDENTIFIER':BUNDLE_ID,
 'INFOPLIST_FILE':'ios/GameLingoAI/InfoDirect.plist' if DIRECT else 'ios/GameLingoAI/Info.plist',
 'CODE_SIGN_ENTITLEMENTS':'' if DIRECT else 'ios/GameLingoAI/GameLingoAI.entitlements',
 'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DIRECT_CAPTURE' if DIRECT else '',
 'PRODUCT_NAME':'GameLingoAI',
 'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon'}
ext_build={**common, 'PRODUCT_BUNDLE_IDENTIFIER':BUNDLE_ID+'.BroadcastUpload',
 'INFOPLIST_FILE':'ios/BroadcastUpload/Info.plist',
 'CODE_SIGN_ENTITLEMENTS':'ios/BroadcastUpload/BroadcastUpload.entitlements',
 'PRODUCT_NAME':'BroadcastUpload','APPLICATION_EXTENSION_API_ONLY':'YES',
 'SKIP_INSTALL':'YES'}

for target,build in [('app',app_build),('ext',ext_build)]:
    for mode in ('Debug','Release'):
        flags={'SWIFT_OPTIMIZATION_LEVEL':'-Onone'} if mode=='Debug' else {'SWIFT_OPTIMIZATION_LEVEL':'-O'}
        obj(f'config:{target}:{mode}','XCBuildConfiguration',buildSettings={**build,**flags,'DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym' if mode=='Release' else 'dwarf'},name=mode)

for mode in ('Debug','Release'):
    obj('config:project:'+mode,'XCBuildConfiguration',buildSettings={
        'CLANG_ENABLE_OBJC_ARC':'YES',
        'ENABLE_STRICT_OBJC_MSGSEND':'YES',
        'GCC_C_LANGUAGE_STANDARD':'gnu17',
        'SWIFT_VERSION':'5.9',
        'CODE_SIGN_STYLE':'Automatic',
        'IPHONEOS_DEPLOYMENT_TARGET':'27.0' if DIRECT else '26.0',
        'SDKROOT':'iphoneos',
    },name=mode)

config_app=obj('configs:app','XCConfigurationList',buildConfigurations=[Raw(oid('config:app:'+mode)) for mode in ('Debug','Release')],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
config_ext=obj('configs:ext','XCConfigurationList',buildConfigurations=[Raw(oid('config:ext:'+mode)) for mode in ('Debug','Release')],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
config_proj=obj('configs:project','XCConfigurationList',buildConfigurations=[Raw(oid('config:project:'+mode)) for mode in ('Debug','Release')],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

target_app=Raw(oid('target:app'))
target_ext=Raw(oid('target:ext'))
proxy=obj('proxy:extension','PBXContainerItemProxy',containerPortal=Raw(oid('project:root')),proxyType=1,remoteGlobalIDString=target_ext,remoteInfo='BroadcastUpload')
target_dependency=obj('dependency:extension','PBXTargetDependency',target=target_ext,targetProxy=proxy)
obj('target:app','PBXNativeTarget',buildConfigurationList=config_app,buildPhases=[sources_app,frameworks_app,resources_app]+([] if DIRECT else [embed_phase]),buildRules=[],dependencies=[] if DIRECT else [target_dependency],name='GameLingoAI',productName='GameLingoAI',productReference=app_product,productType='com.apple.product-type.application')
obj('target:ext','PBXNativeTarget',buildConfigurationList=config_ext,buildPhases=[sources_ext,frameworks_ext,resources_ext],buildRules=[],dependencies=[],name='BroadcastUpload',productName='BroadcastUpload',productReference=ext_product,productType='com.apple.product-type.app-extension')
obj('project:root','PBXProject',attributes={'BuildIndependentTargetsInParallel':True,'LastUpgradeCheck':'1600','TargetAttributes':{str(target_app):{'CreatedOnToolsVersion':'16.0','ProvisioningStyle':'Automatic'},str(target_ext):{'CreatedOnToolsVersion':'16.0','ProvisioningStyle':'Automatic'}}},buildConfigurationList=config_proj,compatibilityVersion='Xcode 14.0',developmentRegion='zh_CN',hasScannedForEncodings=0,knownRegions=['zh_CN','en','Base'],mainGroup=root_group,productRefGroup=prod_group,projectDirPath='',projectRoot='',targets=[target_app] if DIRECT else [target_app,target_ext])

lines=['// !$*UTF8*$!','{','\tarchiveVersion = 1;','\tclasses = {};','\tobjectVersion = 56;','\tobjects = {']
for key,item in sorted(objects.items(),key=lambda kv:(kv[1]['isa'],kv[0])):
    lines.append(f'\t\t{oid(key)} /* {key} */ = {Q(item)};')
lines+=['\t};',f'\trootObject = {oid("project:root")} /* Project object */;','}']
(DEST/'project.pbxproj').write_text('\n'.join(lines)+'\n')
print('Generated',DEST/'project.pbxproj', 'mode:', 'direct-iOS27' if DIRECT else 'replaykit')
