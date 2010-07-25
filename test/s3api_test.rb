require File.join(File.dirname(__FILE__), 'test_helper')

class S3ApiTest < Test::Unit::TestCase

  def test_create
    begin
      AWS::S3::Bucket.find(bucket_name)
    rescue => e
      assert e.instance_of?(AWS::S3::NoSuchBucket)
    end

    begin
      bucket = AWS::S3::Bucket.create(bucket_name)
      assert bucket.instance_of?(AWS::S3::Bucket)
    rescue => e

    end

    begin
      bucket = AWS::S3::Bucket.create(bucket_name)
    rescue => e
      assert e.instance_of?(AWS::S3::BucketAlreadyExists)
    end

    begin
      assert AWS::S3::Bucket.delete(bucket_name)
    rescue => e
    end
  end

  def test_delete
    assert AWS::S3::Bucket.create(bucket_name)
    assert AWS::S3::Bucket.delete(bucket_name)
  end

  def test_upload
    assert AWS::S3::Bucket.create(bucket_name)
    file = File.join(File.dirname(__FILE__), 'file.jpg')
    bucket = AWS::S3::Bucket.find(bucket_name)
    assert bucket.size == 0
    assert S3Object.store('file.jpg', open(file), bucket_name, { :access => :public_read })
    assert bucket.size == 1
    begin
      AWS::S3::Bucket.delete(bucket_name)
    rescue => e
      assert e.instance_of?(AWS::S3::BucketNotEmpty)
      assert AWS::S3::Bucket.delete(bucket_name, :force => true)
    end
  end

  def test_move
    AWS::S3::Bucket.create(bucket_name)
    file = File.join(File.dirname(__FILE__), 'file.jpg')
    S3Object.store('file.jpg', open(file), bucket_name)
    obj = S3Object.find('file.jpg', bucket_name)
    assert obj.rename('new.jpg')

    begin
      AWS::S3::S3Object.find('file.jpg', bucket_name)
    rescue => e
      assert e.instance_of?(AWS::S3::NoSuchKey)
    end

    obj = AWS::S3::S3Object.find('new.jpg', bucket_name)
    assert obj.instance_of?(AWS::S3::S3Object)
    assert AWS::S3::Bucket.delete(bucket_name, :force => true)
  end

  def test_acl
    AWS::S3::Bucket.create(bucket_name, { :access => :public_read })
    bucket = AWS::S3::Bucket.find(bucket_name)
    policy = bucket.acl
    assert policy.owner.id == User.find_by_login('admin').key
    assert policy.grants.include?(:public_read)

    AWS::S3::Bucket.delete(bucket_name, :force => true)
    AWS::S3::Bucket.create(bucket_name)
    bucket = AWS::S3::Bucket.find(bucket_name)
    policy = bucket.acl
    assert !policy.grants.include?(:public_read)
    AWS::S3::Bucket.delete(bucket_name, :force => true)

    AWS::S3::Bucket.create(bucket_name)
    bucket = AWS::S3::Bucket.find(bucket_name)
    bucket.acl.grants << AWS::S3::ACL::Grant.grant(:public_read_acp)
    bucket.acl(bucket.acl)
    assert bucket.acl.grants.include?(:public_read_acp)
    AWS::S3::Bucket.delete(bucket_name, :force => true)
  end

  def test_versioning
    AWS::S3::Bucket.create(bucket_name, { :access => :public_read })
    get "/#{bucket_name}/?versioning"
    assert last_response.ok?
    assert !last_response.body.include?('<Versioning>')
    assert last_response.body.include?('<VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/"></VersioningConfiguration>')

    @user = User.find_by_login('admin')
    sts = hmac_sha1(@user.secret, "PUT\n\ntext/plain\n\n/#{bucket_name}/?versioning")
    aws_header = "AWS " + "#{@user.key}:#{sts}"

    header "Content-Type", "text/plain"
    header "Authorization", aws_header
    xml_data = '<VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Status>Enabled</Status></VersioningConfiguration>';
    put "/#{bucket_name}/?versioning", xml_data
    assert last_response.ok?

    header "Authorization", nil

    get "/#{bucket_name}/?versioning"
    assert last_response.body.include?('<Versioning>Enabled</Versioning>')

    AWS::S3::Bucket.delete(bucket_name, :force => true)
  end

  protected
  def bucket_name
    @bucket_name ||= "test_#{Time.now.to_i}"
  end

end
