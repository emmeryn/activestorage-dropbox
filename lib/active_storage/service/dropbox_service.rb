# frozen_string_literal: true

require "dropbox_api"

module ActiveStorage
  # Wraps the Dropbox Storage as an Active Storage service. See ActiveStorage::Service for the generic API
  # documentation that applies to all services.
  #
  # Dropbox does not support setting file download name via Content-Disposition, see:
  # https://www.dropboxforum.com/t5/Discuss-Developer-API/Content-Disposition-in-dropbox/td-p/340864
  # Until they do, we create a new folder for each file, where folder name is the key while
  # filename is untouched.
  class Service::DropboxService < Service
    def initialize(**config)
      @config = config
    end

    def upload(key, io, checksum: nil, content_type: nil, disposition: nil, filename: nil)
      instrument :upload, key: key, checksum: checksum do
        client.upload_by_chunks "/#{key}/#{filename}", io
      rescue DropboxApi::Errors::UploadError
        raise ActiveStorage::IntegrityError
      end
    end

    def download(key, &block)
      if block_given?
        instrument :streaming_download, key: key do
          stream(key, &block)
        end
      else
        instrument :download, key: key do 
          download_for(key)
        rescue DropboxApi::Errors::NotFoundError
          raise ActiveStorage::FileNotFoundError
        end
      end
    end

    def delete(key)
      instrument :delete, key: key do
        # Contents of folder deleted if path is a folder
        client.delete("/"+key)
      rescue DropboxApi::Errors::NotFoundError
        # Ignore files already deleted
      end
    end

    def delete_prefixed(prefix)
      instrument :delete_prefixed, prefix: prefix do
        client.delete("/"+prefix[0..-2])
      rescue DropboxApi::Errors::NotFoundError
        # Ignore files already deleted
      end
    end

    def exist?(key)
      instrument :exist, key: key do |payload|
        begin
          list_folder_result = client.list_folder(key, { limit: 1 })
          filename = list_folder_result.entries.first.name

          answer = client.get_metadata("/#{key}/#{filename}").present?
        rescue DropboxApi::Errors::NotFoundError
          answer = false
        end
        payload[:exist] = answer
        answer
      end
    end

    def url(key, expires_in:, filename:, disposition:, content_type:)
      instrument :url, key: key do |payload|
        generated_url = file_for(key).link 
        payload[:url] = generated_url
        generated_url
      end
    end

    private

      attr_reader :config

      def file_for(key)
        list_folder_result = client.list_folder("/#{key}", { limit: 1 })
        filename = list_folder_result.entries.first.name

        client.get_temporary_link("/#{key}/#{filename}")
      end

      def download_for(key)
        list_folder_result = client.list_folder("/#{key}", { limit: 1 })
        filename = list_folder_result.entries.first.name

        client.download("/#{key}/#{filename}") do |chunk|
          return chunk.force_encoding(Encoding::BINARY)
        end
      end

      # Reads the file for the given key in chunks, yielding each to the block.
      def stream(key)
        begin
          list_folder_result = client.list_folder("/#{key}", { limit: 1 })
          filename = list_folder_result.entries.first.name

          file = client.download("/#{key}/#{filename}") do |chunk|
            yield chunk
          end
        rescue DropboxApi::Errors::NotFoundError
          raise ActiveStorage::FileNotFoundError
        end
      end

      def client
        @client ||= DropboxApi::Client.new(config.fetch(:access_token))
      end
  end
end