
Puppet::Type.newtype(:acl) do
  desc <<-EOT
     Ensures that a set of ACL permissions are applied to a given file
     or directory.

      Example:

          acl { '/var/www/html':
            action      => exact,
            permission  => [
              'user::rwx',
              'group::r-x',
              'mask::rwx',
              'other::r--',
              'default:user::rwx',
              'default:user:www-data:r-x',
              'default:group::r-x',
              'default:mask::rwx',
              'default:other::r--',
            ],
            provider    => posixacl,
            recursive   => true,
          }

      In this example, Puppet will ensure that the user and group
      permissions are set recursively on /var/www/html as well as add
      default permissions that will apply to new directories and files
      created under /var/www/html
  
      Setting an ACL can change a file's mode bits, so if the file is
      managed by a File resource, that resource needs to set the mode
      bits according to what the calculated mode bits will be, for
      example, the File resource for the ACL above should be:

          file { '/var/www/html':
                 mode => 754,
               }
    EOT

  newparam(:action) do
    desc "What do we do with this list of ACLs? Options are set, unset, exact, and purge"
    newvalues(:set, :unset, :exact, :purge)
    defaultto :set
  end

  newparam(:path) do
    desc "The file or directory to which the ACL applies."
    isnamevar
    validate do |value|
      path = Pathname.new(value)
      unless path.absolute?
        raise ArgumentError, "Path must be absolute: #{path}"
      end
    end
  end

  autorequire(:file) do
    if self[:path]
      [self[:path]]
    end
  end

  newproperty(:permission, :array_matching => :all) do 
    desc "ACL permission(s)."

    def is_to_s(value)
      if value == :absent or value.include?(:absent)
        super
      else
        value.join(",")
      end
    end

    def should_to_s(value)
      if value == :absent or value.include?(:absent)
        super
      else
        value.join(",")
      end
    end

    def retrieve
      provider.permission
    end

    def strip_perms(pl)
      desc = "Remove permission bits from an ACL line, eg:
              user:root:rwx
                becomes
              user:root:"
      Puppet.debug "permission.strip_perms"
      value = []
      pl.each do |perm|
        if !(perm =~ /^(((u(ser)?)|(g(roup)?)|(m(ask)?)|(o(ther)?)):):/)
          perm = perm.split(':')[0..-2].join(':')
          value << perm
        end
      end
      value.sort
    end

    def unset_insync(cur_perm)
      # Puppet.debug "permission.unset_insync"
      cp = strip_perms(cur_perm)
      sp = strip_perms(@should)
      (sp - cp).sort == sp
    end

    def set_insync(cur_perm)
      # Puppet.debug "permission.set_insync"
      (cur_perm.sort == @should.sort) or (provider.check_set and ((@should - cur_perm).length == 0))
    end

    def purge_insync(cur_perm)
      # Puppet.debug "permission.purge_insync"
      cur_perm.each do |perm|
        # If anything other than the mode bits are set, we're not in sync
        if !(perm =~ /^(((u(ser)?)|(g(roup)?)|(o(ther)?)):):/)
          return false
        end
      end
      return true
    end

    def insync?(is)
      cur_perm = provider.permission
      Puppet.debug "permission.insync? cur_perm: #{cur_perm.sort.join(', ')} @should: #{@should.sort.join(', ')}"
      if provider.check_purge
        return purge_insync(cur_perm)
      end
      if provider.check_unset
        return unset_insync(cur_perm)
      end
      return set_insync(cur_perm)
    end

    # TODO munge into normalised form
    validate do |acl|
      unless acl =~ /^(d(efault)?:)?(((u(ser)?|g(roup)?):)?(([^:]+|((m(ask)?|o(ther)?):?))?|:?))(:[-rwxX]+|([0-7]{3,4}))$/
        raise ArgumentError, "%s is not valid acl permission" % acl
      end
    end
  end

  newparam(:recursive) do
    desc "Apply ACLs recursively."
    newvalues(:true, :false)
    defaultto :false
  end

  validate do
    unless self[:permission]
      raise(Puppet::Error, "permission is a required property.")
    end
  end

end
