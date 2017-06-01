require "ood_core/refinements/hash_extensions"

module OodCore
  module BatchConnect
    # A template class that renders a batch script designed to facilitate
    # external connections to the running job
    class Template
      using Refinements::HashExtensions
      using Refinements::ArrayExtensions

      # The context used to render this template
      # @return [Hash] context hash
      attr_reader :context

      # @param context [#to_h] the context used to render the template
      # @option context [#to_s] :work_dir Working directory for batch script
      # @option context [#to_s] :conn_file ("connection.yml") The file that
      #   holds connection information
      # @option context [#to_sym, Array<#to_sym>] :conn_params ([]) A list of
      #   connection parameters added to the connection file (`:host`, `:port`,
      #   and `:password` will always exist)
      # @option context [#to_s] :bash_helpers ("...") Bash helper methods
      # @option context [#to_i] :min_port (2000) Minimum port used when looking
      #   for available port
      # @option context [#to_i] :max_port (65535) Maximum port used when
      #   looking for available port
      # @option context [#to_i] :passwd_size (32) Length of randomly generated
      #   password
      # @option context [#to_s] :script_wrapper ("%s") Bash code that wraps
      #   around the body of the template script (use `%s` to interpolate the
      #   body)
      # @option context [#to_s] :before_script ("...") Bash code run before the
      #   main script is forked off
      # @option context [#to_s] :before_file ("before.sh") Path to script that
      #   is sourced before main script is forked (assumes you don't modify
      #   `:before_script`)
      # @option context [#to_s] :run_script ("...") Bash code that is forked
      #   off and treated as the main script
      # @option context [#to_s] :script_file ("./script.sh") Path to script
      #   that is forked as the main scripta (assumes you don't modify
      #   `:run_script`)
      # @option context [#to_s] :timeout ("") Timeout the main script in
      #   seconds, if empty then let script run for full walltime (assumes you
      #   don't modify `:run_script`)
      # @option context [#to_s] :clean_script ("...") Bash code run during
      #   clean up after job finishes
      # @option context [#to_s] :clean_file ("clean.sh") Path to script that is
      #   sourced during clean up (assumes you don't modify `:clean_script`)
      def initialize(context = {})
        @context = context.to_h.compact.symbolize_keys
        raise ArgumentError, "No work_dir specified. Missing argument: work_dir" unless context.include?(:work_dir)
      end

      # Render this template as string
      # @return [String] rendered template
      def to_s
        <<-EOT.gsub(/^ {10}/, '')
          #!/bin/bash

          #{script_wrapper}
        EOT
      end

      private
        # Working directory that batch script runs in
        def work_dir
          context.fetch(:work_dir).to_s
        end

        # The file that holds the connection information in yaml format
        def conn_file
          context.fetch(:conn_file, "connection.yml").to_s
        end

        # The parameters to include in the connection file
        def conn_params
          conn_params = Array.wrap(context.fetch(:conn_params, [])).map(&:to_sym)
          (conn_params + [:host, :port, :password]).uniq
        end

        # Helper methods used in the bash scripts
        def bash_helpers
          context.fetch(:bash_helpers) do
            min_port    = context.fetch(:min_port, 2000).to_i
            max_port    = context.fetch(:max_port, 65535).to_i
            passwd_size = context.fetch(:passwd_size, 32).to_i

            <<-EOT.gsub(/^ {14}/, '')
              # Generate random integer in range [$1..$2]
              function random () {
                shuf -i ${1}-${2} -n 1
              }

              # Check if port $1 is in use
              function used_port () {
                local PORT=${1}
                nc -z localhost ${PORT} &>/dev/null
              }

              # Find available port in range [$1..$2]
              # Default: [#{min_port}..#{max_port}]
              function find_port () {
                local PORT=$(random ${1:-#{min_port}} ${2:-#{max_port}})
                while $(used_port ${PORT}); do
                  PORT=$(random ${1:-#{min_port}} ${2:-#{max_port}})
                done
                echo ${PORT}
              }

              # Generate random alphanumeric password with $1 (default: #{passwd_size}) characters
              function create_passwd () {
                tr -cd '[:alnum:]' < /dev/urandom 2>/dev/null | head -c${1:-#{passwd_size}}
              }
            EOT
          end.to_s
        end

        # Bash code that wraps around the body of the template script (use `%s`
        # to interpolate the body)
        def script_wrapper
          context.fetch(:script_wrapper, "%s").to_s % base_script
        end

        # Source in a developer defined script before running the main script
        def before_script
          context.fetch(:before_script) do
            before_file = context.fetch(:before_file, "before.sh").to_s

            "host=$(hostname)\n[[ -e \"#{before_file}\" ]] && source \"#{before_file}\""
          end.to_s
        end

        # Fork off a developer defined main script and possibly time it out after
        # a period of time
        def run_script
          context.fetch(:run_script) do
            script_file = context.fetch(:script_file,  "./script.sh").to_s
            timeout     = context.fetch(:timeout, "").to_s

            timeout.empty? ? "\"#{script_file}\"" : "timeout #{timeout} \"#{script_file}\""
          end.to_s
        end

        # Source in a developer defined script after running the main script
        def after_script
          context.fetch(:after_script) do
            after_file = context.fetch(:after_file, "after.sh").to_s

            "[[ -e \"#{after_file}\" ]] && source \"#{after_file}\""
          end.to_s
        end

        # Source in a developer defined clean up script that is run during the
        # clean up stage
        def clean_script
          context.fetch(:clean_script) do
            clean_file = context.fetch(:clean_file, "clean.sh").to_s

            "[[ -e \"#{clean_file}\" ]] && source \"#{clean_file}\""
          end.to_s
        end

        # The base script template
        def base_script
          <<-EOT.gsub(/^ {12}/, '')
            cd #{work_dir}

            # Generate a connection yaml file with given parameters
            function create_yml () {
              echo "Generating connection YAML file..."
              (
                umask 077
                echo -e "#{conn_params.map { |p| "#{p}: $#{p}" }.join('\n')}" > "#{conn_file}"
              )
            }

            # Cleanliness is next to Godliness
            function clean_up () {
              echo "Cleaning up..."
              #{clean_script.gsub(/\n(?=[^\s])/, "\n  ")}
              pkill -P $$
              exit ${1:-0}
            }

            #{bash_helpers}

            #{before_script}

            echo "Script starting..."
            #{run_script} &
            SCRIPT_PID=$!

            #{after_script}

            # Create the connection yaml file
            create_yml

            # Wait for script process to finish
            wait ${SCRIPT_PID} || clean_up 1

            # Exit cleanly
            clean_up
          EOT
        end
    end
  end
end
