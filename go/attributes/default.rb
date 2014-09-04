default[:go][:version] = '1.3'
default[:go][:arch] = RUBY_PLATFORM.match(/64/) ? 'amd64' : '386'
# Handling different OSs makes things too complicated.
# For now, just assume we are always on linux
default[:go][:filename] = "go#{node[:go][:version]}.linux-#{node[:go][:arch]}.tar.gz"

default[:go][:url] = "http://golang.org/dl/#{node[:go][:filename]}"
default[:go][:install_dir] = '/usr/local'
default[:go][:gopath] = '/opt/go'
