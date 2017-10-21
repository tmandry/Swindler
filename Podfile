workspace 'Swindler'
swift_version = '3.0'
platform :osx, '10.10'

use_frameworks!

def testing_pods
  pod 'Quick',  '~> 1.2.0'
  pod 'Nimble', '~> 7.0.2'
end

project 'Swindler'
target 'SwindlerTests' do
  testing_pods
end

target 'Swindler' do
  pod 'PromiseKit', '4.4.0'
  pod 'AXSwift', path: './AXSwift'
end

target 'SwindlerExample' do
  pod 'PromiseKit/CorePromise', '4.4.0'
  pod 'AXSwift', path: './AXSwift'
end
