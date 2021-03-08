require "httparty"
require "json"

require "woocommerce_api/oauth"
require "woocommerce_api/version"

module WooCommerce
  class API

    def initialize url, consumer_key, consumer_secret, args = {}
      # Required args
      @url = url
      @consumer_key = consumer_key
      @consumer_secret = consumer_secret

      # Optional args
      defaults = {
        wp_api: false,
        version: "v3",
        verify_ssl: true,
        signature_method: "HMAC-SHA256",
        httparty_args: {}
      }
      args = defaults.merge(args)

      @wp_api = args[:wp_api]
      @version = args[:version]
      @verify_ssl = args[:verify_ssl] == true
      @signature_method = args[:signature_method]
      @debug_mode = args[:debug_mode]
      @query_string_auth = args[:query_string_auth]
      @httparty_args = args[:httparty_args]

      # Internal args
      @is_ssl = @url.start_with? "https"
    end

    # Public: GET requests.
    #
    # endpoint - A String naming the request endpoint.
    # query    - A Hash with query params.
    #
    # Returns the request Hash.
    def get endpoint, query = nil
      do_request :get, add_query_params(endpoint, query)
    end

    def get_product product_id
      result = self.get("products/#{product_id}")
      begin
        result.parsed_response
      rescue
        # WooCommerce return problem.
        result = result.to_s.split('{')
        JSON.parse('{' + result.drop(1).join('{'))
      end
    end

    def get_attributes
      self.get("products/attributes")
    end

    def get_attributes_terms attribute_id
      self.get("products/attributes/#{attribute_id}/terms?per_page=100")
    end

    def get_variations product_id
      self.get("products/#{product_id}/variations")
    end

    def get_variation product_id, variation_id
      self.get("products/#{product_id}/variations/#{variation_id}")
    end

    # Public: POST requests.
    #
    # endpoint - A String naming the request endpoint.
    # data     - The Hash data for the request.
    #
    # Returns the request Hash.
    def post endpoint, data
      do_request :post, endpoint, data
    end

    def create_product data
      self.post("products", data)
    end

    def create_variation product_id, data
      self.post("products/#{product_id}/variations", data)
    end

    def create_attributes_terms attribute_id, nome
      self.post("products/attributes/#{attribute_id}/terms", { name: nome })
    end

    # Public: PUT requests.
    #
    # endpoint - A String naming the request endpoint.
    # data     - The Hash data for the request.
    #
    # Returns the request Hash.
    def put endpoint, data
      do_request :put, endpoint, data
    end

    def update_product product_id, data
      self.put("products/#{product_id}", data)
    end

    def update_variation product_id, variation_id, data
      self.put("products/#{product_id}/variations/#{variation_id}", data)
    end

    # Public: DELETE requests.
    #
    # endpoint - A String naming the request endpoint.
    # query    - A Hash with query params.
    #
    # Returns the request Hash.
    def delete endpoint, query = nil
      do_request :delete, add_query_params(endpoint, query)
    end

    # Public: OPTIONS requests.
    #
    # endpoint - A String naming the request endpoint.
    #
    # Returns the request Hash.
    def options endpoint
      do_request :options, add_query_params(endpoint, nil)
    end

    protected

    # Internal: Appends data as query params onto an endpoint
    #
    # endpoint - A String naming the request endpoint.
    # data     - A hash of data to flatten and append
    #
    # Returns an endpoint string with the data appended
    def add_query_params endpoint, data
      return endpoint if data.nil? || data.empty?

      endpoint += "?" unless endpoint.include? "?"
      endpoint += "&" unless endpoint.end_with? "?"
      endpoint + URI.encode(flatten_hash(data).join("&"))
    end

    # Internal: Get URL for requests
    #
    # endpoint - A String naming the request endpoint.
    # method   - The method used in the url (for oauth querys)
    #
    # Returns the endpoint String.
    def get_url endpoint, method
      # api = @wp_api ? 'wp-json' : 'wc-api'
      api = @wp_api ? 'wp-json/wc' : 'wc-api'
      
      url = @url
      url = "#{url}/" unless url.end_with? "/"
      url = "#{url}#{api}/#{@version}/#{endpoint}"
      @is_ssl ? url : oauth_url(url, method)
    end

    # Internal: Requests default options.
    #
    # method   - A String naming the request method
    # endpoint - A String naming the request endpoint.
    # data     - The Hash data for the request.
    #
    # Returns the response in JSON String.
    def do_request method, endpoint, data = {}
      url = get_url(endpoint, method)
      options = {
        format: :json
      }

      # Allow custom HTTParty args.
      options = options.merge(@httparty_args)

      # Set headers.
      options[:headers] = {
        "User-Agent" => "WooCommerce API Client-Ruby/#{WooCommerce::VERSION}",
        "Accept" => "application/json"
      }
      options[:headers]["Content-Type"] = "application/json;charset=utf-8" if !data.empty?

      # Set basic authentication.
      if @is_ssl
        options[:verify] = @verify_ssl

        if @query_string_auth
          options.merge!(query: {
            consumer_key: @consumer_key,
            consumer_secret: @consumer_secret
          })
        else
          options.merge!(basic_auth: {
            username: @consumer_key,
            password: @consumer_secret
          })
        end
      end

      options.merge!(debug_output: $stdout) if @debug_mode
      options.merge!(body: data.to_json) if !data.empty?
      HTTParty.send(method, url, options)
    end

    # Internal: Generates an oauth url given current settings
    #
    # url    - A String naming the current request url
    # method - The HTTP verb of the request
    #
    # Returns a url to be used for the query.
    def oauth_url url, method
      oauth = WooCommerce::OAuth.new(
        url,
        method,
        @version,
        @consumer_key,
        @consumer_secret,
        @signature_method
      )
      oauth.get_oauth_url
    end

    # Internal: Flattens a hash into an array of query relations
    #
    # hash - A hash to flatten
    #
    # Returns an array full of key value paired strings
    def flatten_hash hash
      hash.flat_map do |key, value|
        case value
        when Hash
          value.map do |inner_key, inner_value|
            "#{key}[#{inner_key}]=#{inner_value}"
          end
        when Array
          value.map { |inner_value| "#{key}[]=#{inner_value}" }
        else
          "#{key}=#{value}"
        end
      end
    end
  end
end
