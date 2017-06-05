workspace 'Swindler'
swift_version = '3.0'

use_frameworks!

def testing_pods
  pod 'Quick',  '~> 1.1.0'
  pod 'Nimble', '~> 7.0.0'
end

xcodeproj 'Swindler'
target 'SwindlerTests' do
  testing_pods
end
target 'SwindlerTestsProfile' do
  testing_pods
end

target 'Swindler' do
  pod 'PromiseKit', '~> 4.2.0'
end

target 'SwindlerExample' do
  pod 'PromiseKit/CorePromise', '~> 4.2.0'
end
