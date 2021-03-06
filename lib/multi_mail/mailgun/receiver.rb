module MultiMail
  module Receiver
    # Mailgun's incoming email receiver.
    class Mailgun
      include MultiMail::Receiver::Base

      recognizes :mailgun_api_key, :http_post_format

      # Initializes a Mailgun incoming email receiver.
      #
      # @param [Hash] options required and optional arguments
      # @option options [String] :mailgun_api_key a Mailgun API key
      # @option options [String] :http_post_format "parsed" or "raw"
      def initialize(options = {})
        super
        @mailgun_api_key = options[:mailgun_api_key]
        @http_post_format = options[:http_post_format]
      end

      # Returns whether a request originates from Mailgun.
      #
      # @param [Hash] params the content of Mailgun's webhook
      # @return [Boolean] whether the request originates from Mailgun
      # @raise [IndexError] if the request is missing parameters
      # @see http://documentation.mailgun.net/user_manual.html#securing-webhooks
      def valid?(params)
        if @mailgun_api_key
          params.fetch('signature') == signature(params)
        else
          super
        end
      end

      # Transforms the content of Mailgun's webhook into a list of messages.
      #
      # @param [Hash] params the content of Mailgun's webhook
      # @return [Array<MultiMail::Message::Mailgun>] messages
      # @see http://documentation.mailgun.net/user_manual.html#mime-messages-parameters
      # @see http://documentation.mailgun.net/user_manual.html#parsed-messages-parameters
      def transform(params)
        case @http_post_format
        when 'parsed', '', nil
          # Mail changes `self`.
          headers = self.class.multimap(JSON.load(params['message-headers']))
          this = self

          message = Message::Mailgun.new do
            headers headers

            # The following are redundant with `body-mime` in raw MIME format
            # and with `message-headers` in fully parsed format.
            #
            # from    params['from']
            # sender  params['sender']
            # to      params['recipient']
            # subject params['subject']
            #
            # Mailgun POSTs all MIME headers both individually and in
            # `message-headers`.

            text_part do
              body params['body-plain']
            end

            if params.key?('body-html')
              html_part do
                content_type 'text/html; charset=UTF-8'
                body params['body-html']
              end
            end

            if params.key?('attachment-count')
              1.upto(params['attachment-count'].to_i) do |n|
                attachment = params["attachment-#{n}"]
                add_file(this.class.add_file_arguments(attachment))
              end
            end
          end

          # Extra Mailgun parameters.
          if params.key?('stripped-text') && !params['stripped-text'].empty?
            message.stripped_text = params['stripped-text']
          end
          if params.key?('stripped-signature') && !params['stripped-signature'].empty?
            message.stripped_signature = params['stripped-signature']
          end
          if params.key?('stripped-html') && !params['stripped-html'].empty?
            message.stripped_html = params['stripped-html']
          end
          if params.key?('content-id-map') && !params['content-id-map'].empty?
            message.content_id_map = params['content-id-map']
          end

          # @todo Store non-plain, non-HTML body parts.
          # params.keys.select do |key|
          #   key[/\Abody-(?!html|plain)/]
          # end

          [message]
        when 'raw'
          message = self.class.condense(Message::Mailgun.new(Mail.new(params['body-mime'])))
          [message]
        else
          raise ArgumentError, "Can't handle Mailgun #{@http_post_format} HTTP POST format"
        end
      end

      # Returns whether a message is spam.
      #
      # @param [Mail::Message] message a message
      # @return [Boolean] whether the message is spam
      # @see http://documentation.mailgun.net/user_manual.html#spam-filter
      # @note You must enable spam filtering for each domain in Mailgun's [Control
      #   Panel](https://mailgun.net/cp/domains).
      # @note We may also inspect `X-Mailgun-SScore` and `X-Mailgun-Spf`, whose
      #   possible values are "Pass", "Neutral", "Fail" and "SoftFail".
      def spam?(message)
        message['X-Mailgun-Sflag'] && message['X-Mailgun-Sflag'].value == 'Yes'
      end

    private

      def signature(params)
        data = "#{params.fetch('timestamp')}#{params.fetch('token')}"
        OpenSSL::HMAC.hexdigest('sha256', @mailgun_api_key, data)
      end
    end
  end
end
