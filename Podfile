platform :ios, '27.0'
project 'GameLingoAI.xcodeproj'
use_frameworks! :linkage => :static

target 'GameLingoAI' do
  # ML Kit v2's Japanese script model is bundled in the app (offline).
  # Only the separate ios-direct-mlkit-unsigned workflow runs pod install.
  pod 'GoogleMLKit/TextRecognitionJapanese', '9.0.0'
end

# Xcode 27.1 rejects older deployment targets (iOS 9/10/12) still declared by
# some Google ML Kit transitive Pods, despite this app targeting iOS 27.
# Normalize only legacy pod targets, without lowering newer minimums.
post_install do |installer|
  minimum_ios = Gem::Version.new('15.0')
  updated = 0

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |configuration|
      current = configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_s
      next unless current.match?(/\A\d+(?:\.\d+)*\z/)
      next unless Gem::Version.new(current) < minimum_ios

      configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = minimum_ios.to_s
      updated += 1
    end
  end

  puts "[MLKit] Raised #{updated} legacy CocoaPods deployment settings to iOS #{minimum_ios}"
end
