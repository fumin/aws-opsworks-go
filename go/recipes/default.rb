bash 'install-golang' do
  cwd Chef::Config[:file_cache_path]
  code <<-EOH
    rm -rf #{node[:go][:install_dir]}/go
    tar -C #{node[:go][:install_dir]} -zxf #{node[:go][:filename]}
  EOH
  action :nothing
end

remote_file File.join(Chef::Config[:file_cache_path], node[:go][:filename]) do
  source node[:go][:url]
  notifies :run, 'bash[install-golang]', :immediately
  not_if "#{node[:go][:install_dir]}/go/gin/go version | grep go#{node[:go][:version]}"
end

directory "#{node[:go][:gopath]}/src" do
  action :create
  recursive true
end

template '/etc/profile.d/golang.sh' do
  source 'golang.sh.erb'
end
