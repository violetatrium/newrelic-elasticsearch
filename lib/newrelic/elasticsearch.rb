require 'newrelic/elasticsearch/version'
require 'new_relic/agent/method_tracer'
require 'elasticsearch'

DependencyDetection.defer do
  named :elasticsearch

  depends_on do
    defined?(::Elasticsearch::Transport::Client)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Elasticsearch instrumentation'
    require 'newrelic/elasticsearch/operation_resolver'
  end

  executes do
    require 'new_relic/agent/datastores'
    NewRelic::Agent::MethodTracer.extend(NewRelic::Agent::MethodTracer)

    ::Elasticsearch::Transport::Client.class_eval do
      def perform_request_with_new_relic(method, path, params={}, body=nil, headers=nil)
        resolver = NewRelic::ElasticsearchOperationResolver.new(method, path)

        callback = proc do |result, metric, elapsed|
          statement = { body: body, headers: headers, params: params }
          statement[:scope] = resolver.scope
          statement[:additional_parameters] = resolver.operands

          NewRelic::Agent::Datastores.notice_statement(statement.inspect, elapsed) if statement
        end

        NewRelic::Agent::Datastores.wrap('Elasticsearch', resolver.operation_name, resolver.index, callback) do
          @major_version ||= ::Elasticsearch::Transport::VERSION.split('.')[0].to_i
          if @major_version > 5
            perform_request_without_new_relic(method, path, params, body, headers)
          else
            perform_request_without_new_relic(method, path, params, body)
          end
        end
      end

      alias_method :perform_request_without_new_relic, :perform_request
      alias_method :perform_request, :perform_request_with_new_relic
    end
  end
end
