platform :ios, '17.0'

target 'EyePal' do
  use_frameworks!

  pod 'GoogleWebRTC'
  pod 'GoogleMLKit/TextRecognition', '8.0.0'
  pod 'GoogleMLKit/TextRecognitionChinese', '8.0.0'
  pod 'GoogleMLKit/TextRecognitionDevanagari', '8.0.0'
  pod 'GoogleMLKit/TextRecognitionJapanese', '8.0.0'
  pod 'GoogleMLKit/TextRecognitionKorean', '8.0.0'
  pod 'GoogleMLKit/LanguageID', '8.0.0'
  pod 'onnxruntime-objc', '~> 1.24'
  pod 'Yams', '~> 5.0'
  pod 'OpenCV', '~> 4.3.0'

  post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER'] = 'NO'
      end
    end
  end
end
