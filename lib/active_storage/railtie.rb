module ActiveStorageDropbox
  class Railtie < Rails::Railtie
    config.after_initialize do
        ActiveStorage::Blob.class_eval do
          def service_metadata
            if forcibly_serve_as_binary?
              { content_type: ActiveStorage.binary_content_type, disposition: :attachment, filename: filename }
            elsif !allowed_inline?
              { content_type: content_type, disposition: :attachment, filename: filename }
            else
              # filename attribute is always required to upload to Dropbox
              { content_type: content_type, filename: filename }
            end
          end
        end
    end
  end
end