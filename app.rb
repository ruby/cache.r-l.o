require 'open-uri'
require 'uri'
require 'sinatra/base'
require 'erubi'
require 'nokogiri'

class App < Sinatra::Base
  BUCKET_URL = ENV.fetch('BUCKET_URL', 'https://s3.amazonaws.com/ftp.r-l.o')

  helpers do
    def list_objects(prefix)
      token = nil
      contents = []
      prefixes = []
      loop do
        token_param = token ? "&continuous-token=#{URI.encode_www_form_component(token)}" : nil
        xml = Nokogiri::XML(URI.open("#{BUCKET_URL}/?list-type=2&delimiter=/&prefix=#{URI.encode_www_form_component(prefix)}#{token_param}", 'r', &:read))
        result = xml.at('ListBucketResult')
        token = result.at('NextContinuationToken')&.inner_text
        result.search('Contents').each do |content|
          key = content.at('Key').inner_text
          contents.push(
            key: key,
            name: key[prefix.size..-1],
            last_modified: content.at('LastModified').inner_text,
            size: content.at('Size').inner_text,
          )
        end
        result.search('CommonPrefixes').each do |cp|
          prefixes.push(cp.at('Prefix').inner_text)
        end
        break unless token
      end

      [contents, prefixes]
    end
  end

  set :erb, escape_html: true

  get '/*prefix' do
    unless params[:prefix].empty? || params[:prefix][-1] == '/'
      return redirect "#{params[:prefix]}/"
    end

    @prefix = params[:prefix]
    @contents, @prefixes = list_objects(@prefix)

    headers 'Cache-Control' => 'public, max-age=3600'
    erb :list
  end
end
