Pod::Spec.new do |s|
  s.name             = 'adaptive_nav_ios'
  s.version          = '0.1.0'
  s.summary          = 'iPhone Duo geometry for adaptive_nav.'
  s.description      = <<-DESC
Reads the edge of the system's vertical bar, the reserved regions and the hinge
from UIKit and streams them to Dart.
                       DESC
  s.homepage         = 'https://github.com/nightdevcraft/adaptive_nav'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'NightDevCraft' => 'nightdevcraft@yandex.ru' }
  s.source           = { :path => '.' }
  s.source_files     = 'adaptive_nav_ios/Sources/adaptive_nav_ios/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
