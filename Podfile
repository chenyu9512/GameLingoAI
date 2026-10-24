platform :ios, '27.0'
project 'GameLingoAI.xcodeproj'
use_frameworks! :linkage => :static

target 'GameLingoAI' do
  # ML Kit v2's Japanese script model is bundled in the app (offline).
  # Only the separate ios-direct-mlkit-unsigned workflow runs pod install.
  pod 'GoogleMLKit/TextRecognitionJapanese', '9.0.0'
end
