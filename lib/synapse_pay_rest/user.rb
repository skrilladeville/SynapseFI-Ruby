module SynapsePayRest
  class User
    # could do these dynamically but this is probably more readable
    # TODO: Login class? Document class?
    attr_reader :client, :logins, :phone_numbers, :legal_names, :note, :supp_id,
                :is_business, :cip_tag, :documents
    attr_accessor :id, :refresh_token

    class << self
      def find(client:, id:)
        response = client.users.get(user_id: id)
        User.new(
          client: client, 
          id: response['_id'], 
          logins: response['logins'], 
          phone_numbers: response['phone_numbers']
        )
      end

      # TODO: cache response and have some parameter for force re-fetch
      def all(client:, page: 1, per_page: 15)
        response = client.users.get(options: {page: page, per_page: per_page})
        response['users'].map do |data|
          args = {
            client: client,
            logins: data['logins'],
            phone_numbers: data['phone_numbers'],
            legal_names: data['legal_names'],
            supp_id: data['extra']['supp_id'],
            is_business: data['extra']['is_business'],
            cip_tag: data['extra']['cip_tag']
          }
          user = User.new(args)
          user.id = data['_id']
          user.refresh_token = data['refresh_token']
          user
        end
      end
    end

    # provide id for existing user or required fields for new user
    # TODO: handle error if id not found
    def initialize(client:, id: nil, **options)
      @client = client
      @documents = []

      if id
        @id = id
        fetch_info(id: id)
      else
        validate_minimal_initialization_args(options)
        api_create_user(options)
      end

      @client.users.client.user_id = @id
    end

    # TODO: validate some kind of proper input was entered
    def update(**options)
      payload = {
        'refresh_token' => refresh_token,
        'update' => {}
      }
      # must have one of these
      payload['update']['login'] = options[:login] if options[:login]
      payload['update']['remove_login'] = options[:remove_login] if options[:remove_login]
      payload['update']['legal_name'] = options[:legal_name] if options[:legal_name]
      payload['update']['phone_number'] = options[:phone_number] if options[:phone_number]
      payload['update']['remove_phone_number'] = options[:remove_phone_number] if options[:remove_phone_number]

      client.users.update(payload: payload)
    end

    # TOOD: validate input type
    def add_documents(*documents)
      payload = {
        'documents' => [{
          'email' => documents.first.email,
          'phone_number' => documents.first.phone_number,
          'ip' => documents.first.ip,
          'name' => documents.first.name,
          'alias' => documents.first.alias,
          'entity_type' => documents.first.entity_type,
          'entity_scope' => documents.first.entity_scope,
          'day' => documents.first.birth_day,
          'month' => documents.first.birth_month,
          'year' => documents.first.birth_year,
          'address_street' => documents.first.address_street,
          'address_city' => documents.first.address_city,
          'address_subdivision' => documents.first.address_subdivision,
          'address_postal_code' => documents.first.address_postal_code,
          'address_country_code' => documents.first.address_country_code
        }]
      }

      # add docs to payload
      documents.each do |doc|
        if doc.category == :physical
          payload['documents'].first['physical_docs'] ||= []
          document = {'document_value' => doc.value, 'document_type' => doc.type}
          payload['documents'].first['physical_docs'] << document
        elsif doc.category == :virtual
          payload['documents'].first['virtual_docs'] ||= []
          document = {'document_value' => doc.value, 'document_type' => doc.type}
          payload['documents'].first['virtual_docs'] << document
        elsif doc.category == :social
          payload['documents'].first['social_docs'] ||= []
          document = {'document_value' => doc.value, 'document_type' => doc.type}
          payload['documents'].first['social_docs'] << document
        end
      end

      authenticate
      client.users.update(payload: payload)
      @documents.concat(documents)
    end

    # def create_node(node)
    #   @nodes << node
    # end

    # def nodes
    # end

    private

    # TODO: validate format of each arg as well
    # TODO: allow single (e.g. email:/password:) as well as array args email/password in lieue of logins array
    # TODO: allow login hash to use symbol keys
    def validate_minimal_initialization_args(args)
      required_params = [:logins, :phone_numbers, :legal_names]
      required_params.each do |arg|
        unless args[arg]
          raise ArgumentError, "must initialize #{self.class} with either id or #{required_params.join('/')}"
        end
      end
    end

    # def add_login(email:, password: nil)
    # end

    # TODO: assign all data from response to instance methods (iterating through and creating documents, etc)
    def fetch_info(id:)
      response = client.users.get(user_id: id)
      @logins = response['logins']
      @phone_numbers = response['phone_numbers']
      @legal_names = response['legal_names']
      @supp_id = response['extra']['supp_id']
      @is_business = response['extra']['is_business']
      @cip_tag = response['extra']['cip_tag']
      @refresh_token = response['refresh_token']

      documents_from_response(response)
    end

    # TODO: refactor for DRYness
    def documents_from_response(response)
      @documents = []
      response['documents'].each do |cip_doc|
        physical_docs = cip_doc['physical_docs'].map do |doc_info|
          details = {
            category: :physical,
            id: doc_info['id'],
            type: doc_info['document_type'],
            status: doc_info['status']
          }
          doc = Document.new(details)
        end
        social_docs = cip_doc['social_docs'].map do |doc_info|
          details = {
            category: :social,
            id: doc_info['id'],
            type: doc_info['document_type'],
            status: doc_info['status']
          }
          doc = Document.new(details)
        end
        virtual_docs = cip_doc['virtual_docs'].map do |doc_info|
          details = {
            category: :virtual,
            id: doc_info['id'],
            type: doc_info['document_type'],
            status: doc_info['status']
          }
          doc = Document.new(details)
        end
        @documents.concat([physical_docs, social_docs, virtual_docs].flatten)
      end
    end

    def api_create_user(info)
      payload = {
        'logins' => info[:logins],
        'phone_numbers' => info[:phone_numbers],
        'legal_names' => info[:legal_names],
        'extra' => {}
      }
      # optional
      payload['extra']['note'] = info[:note] if info[:note]
      payload['extra']['supp_id'] = info[:supp_id] if info[:supp_id]
      payload['extra']['is_business'] = info[:is_business] if info[:is_business]

      response = client.users.create(payload: payload)
      
      @refresh_token = response['refresh_token']
      @id = response['_id']
      info.each { |key, value| instance_variable_set("@#{key}", value) }
    end

    def authenticate
      client.users.refresh(payload: {'refresh_token' => refresh_token})
    end
  end
end