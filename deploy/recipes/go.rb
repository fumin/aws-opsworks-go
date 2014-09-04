include_recipe 'deploy'
include_recipe 'go'

require 'uri'
def go_package_name_from_repository(repository)
  repo_uri = URI(repository)
  no_ext = File.basename(repo_uri.path, File.extname(repo_uri.path))
  "#{repo_uri.host}#{File.dirname(repo_uri.path)}/#{no_ext}"
rescue URI::InvalidURIError
  # Try the git scp-like syntax [user@]host.xz:path/to/repo.git/
  m = %r{(\w+@)?([\w\.]+):(.+)}.match(repository)
  no_ext = File.basename(m[3], File.extname(m[3]))
  "#{m[2]}/#{File.dirname(m[3])}/#{no_ext}"
end

node[:deploy].each do |application, deploy|
  # Clone our application source code to deploy[:deploy_to]
  # Opsworks actually maintains a few versions of our app under folders with the
  # pattern "#{deploy[:deploy_to]}/releases/#{timestamp}",
  # plus a symlink "#{deploy[:deploy_to]}/current" pointing to the latest release.
  # Indeed, the opsworks::deploy cookbook follows closely to that of
  # http://docs.opscode.com/chef/resources.html#deploy
  opsworks_deploy_dir do
    user deploy[:user]
    group deploy[:group]
    path deploy[:deploy_to]
  end
  opsworks_deploy do
    deploy_data deploy
    app application
  end

  # opsworks_deploy creates some stub dirs, which are not needed for typical webapps
  # This is copied from github.com/aws/opsworks-cookbooks/deploy/recipes/java.rb
  current_dir = ::File.join(deploy[:deploy_to], 'current')
  ruby_block "remove unnecessary directory entries in #{current_dir}" do
    block do
      ['config', 'log', 'public', 'tmp'].each do |dir_entry|
        ::FileUtils.rm_rf(::File.join(current_dir, dir_entry), :secure => true)
      end
    end
  end

  # Copy the current release to the package folder under $GOPATH
  package_path = go_package_name_from_repository(deploy[:scm][:repository])
  package_dir = "#{node[:go][:gopath]}/src/#{package_path}"
  ruby_block "copy to gopath" do
    block do
      require 'fileutils'
      FileUtils.rm_rf package_dir
      FileUtils.mkdir_p package_dir
      FileUtils.cp_r Dir["#{current_dir}/*"], package_dir
    end
  end

  gocmd = "#{node[:go][:install_dir]}/go/bin/go"
  ENV['GOPATH'] = node[:go][:gopath]

  execute "get go app" do
    command "#{gocmd} get #{package_path}/..."
    notifies :run, 'bash[start go app]', :immediately
    action :run
  end

  bash "start go app" do
    # Change to the package directory so that templates can be found through
    # relative paths in golang source code.
    cwd package_dir
    package_name = File.basename(package_path)
    binary = "#{node[:go][:gopath]}/bin/#{package_name}"
    opts = ["-host=#{node[:opsworks][:instance][:private_ip]}",
            "-port=#{node[:webserver][:port]}",
            "-logtostderr=#{node[:glog][:logtostderr]}",
            "-stderrthreshold=#{node[:glog][:stderrthreshold]}",
    
            "-appid=#{node[:opsworks][:stack][:name]}",
           ].join(' ')
    Chef::Log.info("Starting go app: #{binary} #{opts}")
    logfile = "#{deploy[:deploy_to]}/shared/log/#{package_name}.log"
    # TODO: this should be an upstart script
    code <<-EOF 
      kill `ps -ef | grep #{binary} | grep -v grep | awk '{ print $2 }'`
      nohup #{binary} #{opts} > #{logfile} 2>&1 &
    EOF
    action :nothing
  end
end
