require 'java'

require 'jruby-rack'
require 'trinidad/jars'

module Trinidad

  require 'trinidad/version'
  require 'trinidad/configuration'
  require 'trinidad/server'
  require 'trinidad/web_app'

  autoload :CLI, 'trinidad/cli'
  autoload :Extensions, 'trinidad/extensions'
  autoload :Helpers, 'trinidad/helpers'
  autoload :Logging, 'trinidad/logging'

  module Lifecycle

    autoload :Base, 'trinidad/lifecycle/base'
    autoload :Host, 'trinidad/lifecycle/host'

    module WebApp

      require 'trinidad/lifecycle/web_app/shared'

      autoload :Default, 'trinidad/lifecycle/web_app/default'
      autoload :War, 'trinidad/lifecycle/web_app/war'

    end

  end
end