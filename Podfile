platform :ios, '27.0'
project 'GameLingoAI.xcodeproj'
use_frameworks! :linkage => :static

target 'GameLingoAI' do
  # On-device PaddleOCR recognition with Vision-based text region detection.
  # No Google ML Kit or external OCR API.
  pod 'onnxruntime-objc', '~> 1.24'
end

post_install do |installer|
  minimum = Gem::Version.new('15.0')
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER'] = 'NO'
      current = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_s
      if current.match?(/\A\d+(?:\.\d+)*\z/) && Gem::Version.new(current) < minimum
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = minimum.to_s
      end
    end
  end
end
