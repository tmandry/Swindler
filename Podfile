workspace 'Swindler'
swift_version = '4.0'
platform :osx, '10.10'

use_frameworks!

project 'Swindler'

target 'SwindlerTests' do
  pod 'Quick', git: 'https://github.com/pcantrell/Quick.git', branch: 'around-each'
  pod 'Nimble', '~> 7.3.1'
end

target 'Swindler' do
  pod 'PromiseKit/CorePromise', '~> 6.0'
  pod 'AXSwift', path: './AXSwift'
end

target 'SwindlerExample' do
  pod 'PromiseKit/CorePromise', '~> 6.0'
  pod 'AXSwift', path: './AXSwift'
end
