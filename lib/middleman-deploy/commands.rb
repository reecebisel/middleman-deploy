require "middleman-core/cli"

require "middleman-deploy/extension"
require "middleman-deploy/pkg-info"

require "git"

PACKAGE = "#{Middleman::Deploy::PACKAGE}"
VERSION = "#{Middleman::Deploy::VERSION}"

module Middleman
  module Cli

    # This class provides a "deploy" command for the middleman CLI.
    class Deploy < Thor
      include Thor::Actions

      check_unknown_options!

      namespace :deploy

      # Tell Thor to exit with a nonzero exit code on failure
      def self.exit_on_failure?
        true
      end

      desc "deploy", "Deploy build directory to a remote host via rsync or git"
      method_option "clean",
      :type => :boolean,
      :aliases => "-c",
      :desc => "Remove orphaned files or directories on the remote host"
      def deploy
        send("deploy_#{self.deploy_options.method}")
      end

      protected

      def print_usage_and_die(message)
        raise Error, "ERROR: " + message + "\n" + <<EOF

You should follow one of the two examples below to setup the deploy
extension in config.rb.

# To deploy the build directory to a remote host via rsync:
activate :deploy do |deploy|
  deploy.method = :rsync
  # host, user, and path *must* be set
  deploy.user = "tvaughan"
  deploy.host = "www.example.com"
  deploy.path = "/srv/www/site"
  # clean is optional (default is false)
  deploy.clean = true
end

# To deploy to a remote branch via git (e.g. gh-pages on github):
activate :deploy do |deploy|
  deploy.method = :git
  # remote is optional (default is "origin")
  # run `git remote -v` to see a list of possible remotes
  deploy.remote = "some-other-remote-name"
  # branch is optional (default is "gh-pages")
  # run `git branch -a` to see a list of possible branches
  deploy.branch = "some-other-branch-name"
end

# To deploy the build directory to a remote host via ftp:
activate :deploy do |deploy|
  deploy.method = :ftp
  # host, user, passwword and path *must* be set
  deploy.host = "ftp.example.com"
  deploy.user = "tvaughan"
  deploy.password = "secret"
  deploy.path = "/srv/www/site"
end
EOF
      end

      def deploy_options
        options = nil

        begin
          options = ::Middleman::Application.server.inst.options
        rescue
          print_usage_and_die "You need to activate the deploy extension in config.rb."
        end

        if (!options.method)
          print_usage_and_die "The deploy extension requires you to set a method."
        end

        if (options.method == :rsync)
          if (!options.host || !options.user || !options.path)
            print_usage_and_die "The rsync deploy method requires host, user, and path to be set."
          end
        end

        options
      end

      def deploy_rsync
        host = self.deploy_options.host
        port = self.deploy_options.port
        user = self.deploy_options.user
        path = self.deploy_options.path

        puts "## Deploying via rsync to #{user}@#{host}:#{path} port=#{port}"

        command = "rsync -avze '" + "ssh -p #{port}" + "' build/ #{user}@#{host}:#{path}"

        if options.has_key? "clean"
          clean = options.clean
        else
          clean = self.deploy_options.clean
        end

        if clean
          command += " --delete"
        end

        run command
      end

      def deploy_git
        remote = self.deploy_options.remote
        branch = self.deploy_options.branch

        puts "## Deploying via git to remote=\"#{remote}\" and branch=\"#{branch}\""

        # ensure that the remote branch exists in ENV["MM_ROOT"]
        orig = Git.open(ENV["MM_ROOT"])
        # TODO: orig.branch(branch, "#{remote}/#{branch}")

        Dir.mktmpdir do |tmp|
          # clone ENV["MM_ROOT"] to tmp (ENV["MM_ROOT"] is now "origin")
          repo = Git.clone(ENV["MM_ROOT"], tmp)
          repo.checkout("origin/#{branch}", :new_branch => branch)

          # copy ./build/* to tmp
          FileUtils.cp_r(Dir.glob(File.join(ENV["MM_ROOT"], "build", "*")), tmp)

          # git add and commit in tmp
          repo.add
          repo.commit("Automated commit at #{Time.now.utc} by #{PACKAGE} #{VERSION}")

          # push back into ENV["MM_ROOT"]
          repo.push("origin", branch)
        end

        orig.push(remote, branch)
        orig.remote(remote).fetch
      end

      def deploy_ftp
        require 'net/ftp'
        require 'ptools'

        host = self.deploy_options.host
        user = self.deploy_options.user
        pass = self.deploy_options.password
        path = self.deploy_options.path

        puts "## Deploying via ftp to #{user}@#{host}:#{path}"

        ftp = Net::FTP.new(host)
        ftp.login(user, pass)
        ftp.chdir(path)
        ftp.passive = true

        Dir.chdir('build/') do
          Dir['**/*'].each do |f|
            if File.directory?(f)
              begin
                ftp.mkdir(f)
              rescue
                puts "Folder '#{f}' exists. skipping..."
              end
            else
              begin
                if File.binary?(f)
                  ftp.putbinaryfile(f, f)
                else
                  ftp.puttextfile(f, f)
                end
              rescue Exception => e
                reply = e.message
                err_code = reply[0,3].to_i
                if err_code == 550
                  if File.binary?(f)
                    ftp.putbinaryfile(f, f)
                  else
                    ftp.puttextfile(f, f)
                  end
                end
              end
            end
          end
        end
        ftp.close
      end

    end

    # Alias "d" to "deploy"
    Base.map({ "d" => "deploy" })

  end
end
