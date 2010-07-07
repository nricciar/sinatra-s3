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
    assert S3Object.store(file, open(file), bucket_name, { :access => :public_read })
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
    assert policy.owner.id == '44CF9590006BF252F707'
    assert policy.grants.include?(:public_read)

    AWS::S3::Bucket.delete(bucket_name, :force => true)
    AWS::S3::Bucket.create(bucket_name)
    bucket = AWS::S3::Bucket.find(bucket_name)
    policy = bucket.acl
    assert !policy.grants.include?(:public_read)
    AWS::S3::Bucket.delete(bucket_name, :force => true)
  end

  protected
  def bucket_name
    @bucket_name ||= "test_#{Time.now.to_i}"
  end

end
