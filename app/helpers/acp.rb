module S3
  module Helpers
    module ACP

      # Kick out any users which do not have acp read access to a certain resource.
      def only_can_read_acp bit; raise S3::AccessDenied unless bit.acp_readable_by? @user end
      # Kick out any users which do not have acp write access to a certain resource.
      def only_can_write_acp bit; raise S3::AccessDenied unless bit.acp_writable_by? @user end

      def acl_response_for(bit)
        only_can_read_acp(bit)

        xml do |x|
          x.AccessControlPolicy :xmlns => "http://s3.amazonaws.com/doc/2006-03-01/" do
            x.Owner do
              x.ID bit.owner.key
              x.DisplayName bit.owner.login
            end
            x.AccessControlList do
              bit.acl_list.each_pair do |key,acl|
                x.Grant do
                  x.Grantee "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance", "xsi:type" => acl[:type] do
                    if acl[:type] == "CanonicalUser"
                      x.ID acl[:id]
                      x.DisplayName acl[:name]
                    else
                      x.URI acl[:uri]
                    end
                  end
                  x.Permission acl[:access]
                end
              end
            end
          end
        end
      end

      # Parse any ACL requests which have come in.
      def requested_acl(slot=nil)
        if slot && params.has_key?('versioning')
          only_can_write_acp slot
          env['rack.input'].rewind
          data = env['rack.input'].read
          xml_request = REXML::Document.new(data).root

          # check if we are enabling version control
          # FIXME: does not disable version control
          if !slot.versioning_enabled? && xml_request.elements['Status'].text == 'Enabled'
            raise NotImplemented unless defined?(Git)
            slot.git_init
          end
        elsif slot && params.has_key?('acl')
          only_can_write_acp slot
          env['rack.input'].rewind
          data = env['rack.input'].read
          xml_request = REXML::Document.new(data).root
          xml_request.each_element('//Grant') do |element|
            new_perm = element.elements['Permission'].text
            new_access = "#{Models::Bit.acl_text.invert[new_perm]}00".to_i(8)
            grantee = element.elements['Grantee']

            case grantee.attributes["type"]
            when "CanonicalUser"
              user_check = Models::User.find_by_key(grantee.elements["ID"].text)
              unless user_check.nil? || slot.owner.id == user_check.id
                update_user_access(slot,user_check,new_access)
              end
            when "Group"
              if grantee.elements['URI'].text =~ /AuthenticatedUsers/
                slot.access &= ~(slot.access.to_s(8)[1,1].to_i*10)
                slot.access |= (Models::Bit.acl_text.invert[new_perm]*10).to_s.to_i(8)
              end
              if grantee.elements['URI'].text =~ /AllUsers/
                slot.access &= ~slot.access.to_s(8)[2,1].to_i
                slot.access |= Models::Bit.acl_text.invert[new_perm].to_s.to_i(8)
              end
              slot.save()
            when "AmazonCustomerByEmail"
              user_check = Models::User.find_by_email(grantee.elements["EmailAddress"].text)
              unless user_check.nil? || slot.owner.id == user_check.id
                update_user_access(slot,user_check,new_access)
              end
            when ""
            else
              raise NotImplemented
            end
          end
          {}
        else
          {:access => CANNED_ACLS[@amz['acl']] || CANNED_ACLS['private']}
        end
      end

    end
  end
end
