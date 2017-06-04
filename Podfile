workspace 'Swindler'

use_frameworks!

def testing_pods
  pod 'Quick', '~> 0.8.0'
  pod 'Nimble', '~> 4.0.0'
end

xcodeproj 'Swindler'
target 'SwindlerTests' do
  testing_pods
end
target 'SwindlerTestsProfile' do
  testing_pods
end

target 'Swindler' do
  pod 'PromiseKit/CorePromise', '~> 3.0.0'
#  pod 'PromiseKit/Foundation', '~> 3.0.0'
end

target 'SwindlerExample' do
  pod 'PromiseKit/CorePromise', '~> 3.0.0'
end
