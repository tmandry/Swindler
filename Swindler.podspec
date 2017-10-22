Pod::Spec.new do |s|
  s.name         = 'Swindler'
  s.version      = '0.0.1'
  s.summary      = 'macOS window management framework, written in Swift'

  # This description is used to generate tags and improve search results.
  #   * Think: What does it do? Why did you write it? What is the focus?
  #   * Try to keep it short, snappy and to the point.
  #   * Write the description between the DESC delimiters below.
  #   * Finally, don't worry about the indent, CocoaPods strips it!
  s.description  = <<-DESC
    Swindler makes it easy to write window managers for macOS in Swift with a type-safe,
    promise-based API on top of the low-level accessibility APIs.
                   DESC

  s.homepage     = 'https://github.com/tmandry/Swindler'

  s.license      = { type: 'MIT', file: 'LICENSE' }

  s.author             = { 'Tyler Mandry' => 'tmandry@gmail.com' }
  s.social_media_url   = 'http://twitter.com/tmandry'

  # ――― Platform Specifics ――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  If this Pod runs only on iOS or OS X, then specify the platform and
  #  the deployment target. You can optionally include the target after the platform.
  #

  s.platform     = :osx, '10.10'

  s.source       = { :git => 'https://github.com/tmandry/Swindler.git', :commit => 'c2b871e1d4f47b82b87510fed6ca320f97e3f2d0' }# :tag => s.version.to_s }

  s.source_files = 'Sources', 'Sources/**/*.{h,swift}'
  s.public_header_files = 'Sources/ASLLog/ASLLog.h'

  s.pod_target_xcconfig = {'SWIFT_INCLUDE_PATHS' => '$(SRCROOT)/Swindler/Sources/ASLLog/**',
                           'LIBRARY_SEARCH_PATHS' => '$(SRCROOT)/Swindler/Sources/ASLLog'}
  s.preserve_paths = 'Sources/ASLLog/module.modulemap'

  s.dependency 'PromiseKit', '4.4.0'
  s.dependency 'AXSwift', '0.2.0'

  s.frameworks = 'Cocoa'
end
