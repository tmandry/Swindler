Pod::Spec.new do |s|
  s.name         = 'Swindler'
  s.version      = '0.1.0'
  s.summary      = 'A fork of tmandry\'s macOS window management framework'

  # This description is used to generate tags and improve search results.
  #   * Think: What does it do? Why did you write it? What is the focus?
  #   * Try to keep it short, snappy and to the point.
  #   * Write the description between the DESC delimiters below.
  #   * Finally, don't worry about the indent, CocoaPods strips it!
  s.description  = <<-DESC
    Swindler makes it easy to write window managers for macOS in Swift with a type-safe,
    promise-based API on top of the low-level accessibility APIs.
                   DESC

  s.homepage          = 'https://github.com/robertkarl/Swindler'
  s.documentation_url = "https://tmandry.github.io/Swindler/docs/#{s.version.to_s}"

  s.license      = { type: 'MIT', file: 'LICENSE' }

  s.author             = { 'Tyler Mandry' => 'tmandry@gmail.com' }

  s.platform     = :osx, '10.10'

  s.source       = { git: 'https://github.com/tmandry/Swindler.git', tag: s.version.to_s }

  s.source_files = 'Sources', 'Sources/**/*.{h,swift}'

  s.dependency 'PromiseKit/CorePromise', '~> 6.0'
  s.dependency 'AXSwift', '0.2.3'

  s.frameworks = 'Cocoa'
end
