require_relative "utils"

if defined?(OpenSSL) && defined?(OpenSSL::Timestamp)

class OpenSSL::TestTimestamp < OpenSSL::TestCase
  def intermediate_key
    @intermediate_key ||= OpenSSL::PKey::RSA.new <<-_end_of_pem_
-----BEGIN RSA PRIVATE KEY-----
MIICWwIBAAKBgQCcyODxH+oTrr7l7MITWcGaYnnBma6vidCCJjuSzZpaRmXZHAyH
0YcY4ttC0BdJ4uV+cE05IySVC7tyvVfFb8gFQ6XJV+AEktP+XkLbcxZgj9d2NVu1
ziXdI+ldXkPnMhyWpMS5E7SD6gflv9NhUYEsmAGsUgdK6LDmm2W2/4TlewIDAQAB
AoGAYgx6KDFWONLqjW3f/Sv/mGYHUNykUyDzpcD1Npyf797gqMMSzwlo3FZa2tC6
D7n23XirwpTItvEsW9gvgMikJDPlThAeGLZ+L0UbVNNBHVxGP998Nda1kxqKvhRE
pfZCKc7PLM9ZXc6jBTmgxdcAYfVCCVUoa2mEf9Ktr3BlI4kCQQDQAM09+wHDXGKP
o2UnCwCazGtyGU2r0QCzHlh9BVY+KD2KjjhuWh86rEbdWN7hEW23Je1vXIhuM6Pa
/Ccd+XYnAkEAwPZ91PK6idEONeGQ4I3dyMKV2SbaUjfq3MDL4iIQPQPuj7QsBO/5
3Nf9ReSUUTRFCUVwoC8k4Z1KAJhR/K/ejQJANE7PTnPuGJQGETs09+GTcFpR9uqY
FspDk8fg1ufdrVnvSAXF+TJewiGK3KU5v33jinhWQngRsyz3Wt2odKhEZwJACbjh
oicQqvzzgFd7GzVKpWDYd/ZzLY1PsgusuhoJQ2m9TVRAm4cTycLAKhNYPbcqe0sa
X5fAffWU0u7ZwqeByQJAOUAbYET4RU3iymAvAIDFj8LiQnizG9t5Ty3HXlijKQYv
y8gsvWd4CdxwOPatWpBUX9L7IXcMJmD44xXTUvpbfQ==
-----END RSA PRIVATE KEY-----
_end_of_pem_
  end

  def ee_key
    @ee_key ||= OpenSSL::PKey::RSA.new <<-_end_of_pem_
-----BEGIN RSA PRIVATE KEY-----
MIICWwIBAAKBgQDA6eB5r2O5KOKNbKMBhzadl43lgpwqq28m+G0gH38kKCL1f3o9
P8xUZm7sZqcWEervZMSSXMGBV9DgeoSR+U6FMJywgQGx/JNRx7wZTMNym3PvgLkl
xCXh6ZA0/xbtJtcNI+UUv0ENBkTIuUWBhkAf3jQclAr9aQ0ktYBuHAcRcQIDAQAB
AoGAKNhcAuezwZx6e18pFEXAtpVEIfgJgK9TlXi8AjUpAkrNPBWFmDpN1QDrM3p4
nh+lEpLPW/3vqqchPqYyM4YJraMLpS3KUG+s7+m9QIia0ri2WV5Cig7WL+Tl9p7K
b3oi2Aj/wti8GfOLFQXOQQ4Ea4GoCv2Sxe0GZR39UBxzTsECQQD1zuVIwBvqU2YR
8innsoa+j4u2hulRmQO6Zgpzj5vyRYfA9uZxQ9nKbfJvzuWwUv+UzyS9RqxarqrP
5nQw5EmVAkEAyOmJg6+AfGrgvSWfSpXEds/WA/sHziCO3rE4/sd6cnDc6XcTgeMs
mT8Z3kAYGpqFDew5orUylPfJJa+PUueJbQJAY+gkvw3+Cp69FLw1lgu0wo07fwOU
n2qu3jsNMm0DOFRUWfTAMvcd9S385L7WEnWZldUfnKK1+OGXYYrMXPbchQJAChU2
UoaHQzc16iguM1cK0g+iJPb/MEgQA3sPajHmokGpxIm2T+lvvo0dJjs/Om6QyN8X
EWRYkoNQ8/Q4lCeMjQJAfvDIGtyqF4PieFHYgluQAv5pGgYpakdc8SYyeRH9NKey
GaL27FRs4fRWf9OmxPhUVgIyGzLGXrueemvQUDHObA==
-----END RSA PRIVATE KEY-----
_end_of_pem_
  end

  def ca_cert
    @ca_cert ||= OpenSSL::Certs.ca_cert
  end


  def ts_cert_direct
    @ts_cert_direct ||= OpenSSL::Certs.ts_cert_direct(ee_key, ca_cert)
  end

  def intermediate_cert
    @intermediate_cert ||= OpenSSL::Certs.intermediate_cert(intermediate_key, ca_cert)
  end

  def ts_cert_ee
    @ts_cert_ee ||= OpenSSL::Certs.ts_cert_ee(ee_key, intermediate_cert, intermediate_key)
  end

  def test_create_request
    req = OpenSSL::Timestamp::Request.new
    assert_equal(true, req.cert_requested?)
    assert_equal(1, req.version)
    assert_nil(req.algorithm)
    assert_equal("", req.message_imprint)
    assert_nil(req.policy_id)
    assert_nil(req.nonce)
  end

  def test_request_mandatory_fields
    req = OpenSSL::Timestamp::Request.new
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      tmp = req.to_der
      pp OpenSSL::ASN1.decode(tmp)
    end
    req.algorithm = "sha1"
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      req.to_der
    end
    req.message_imprint = OpenSSL::Digest::SHA1.new.digest("data")
    req.to_der
  end

  def test_request_assignment
    req = OpenSSL::Timestamp::Request.new

    req.version = 2
    assert_equal(2, req.version)
    assert_raises(TypeError) { req.version = nil }
    assert_raises(TypeError) { req.version = "foo" }

    req.algorithm = "SHA1"
    assert_equal("SHA1", req.algorithm)
    assert_raises(TypeError) { req.algorithm = nil }
    assert_raises(OpenSSL::ASN1::ASN1Error) { req.algorithm = "xxx" }

    req.message_imprint = "test"
    assert_equal("test", req.message_imprint)
    assert_raises(TypeError) { req.message_imprint = nil }

    req.policy_id = "1.2.3.4.5"
    assert_equal("1.2.3.4.5", req.policy_id)
    assert_raises(TypeError) { req.policy_id = 123 }
    assert_raises(TypeError) { req.policy_id = nil }

    req.nonce = 42
    assert_equal(42, req.nonce)
    assert_raises(TypeError) { req.nonce = "foo" }
    assert_raises(TypeError) { req.nonce = nil }

    req.cert_requested = false
    assert_equal(false, req.cert_requested?)
    req.cert_requested = nil
    assert_equal(false, req.cert_requested?)
    req.cert_requested = 123
    assert_equal(true, req.cert_requested?)
    req.cert_requested = "asdf"
    assert_equal(true, req.cert_requested?)
  end

  def test_request_re_assignment
    #tests whether the potential 'freeing' of previous values in C works properly
    req = OpenSSL::Timestamp::Request.new
    req.version = 2
    req.version = 3
    req.algorithm = "SHA1"
    req.algorithm = "SHA256"
    req.message_imprint = "test"
    req.message_imprint = "test2"
    req.policy_id = "1.2.3.4.5"
    req.policy_id = "1.2.3.4.6"
    req.nonce = 42
    req.nonce = 24
    req.cert_requested = false
    req.cert_requested = true
    req.to_der
  end

  def test_request_encode_decode
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.policy_id = "1.2.3.4.5"
    req.nonce = 42

    qer = OpenSSL::Timestamp::Request.new(req.to_der)
    assert_equal(1, qer.version)
    assert_equal("SHA1", qer.algorithm)
    assert_equal(digest, qer.message_imprint)
    assert_equal("1.2.3.4.5", qer.policy_id)
    assert_equal(42, qer.nonce)

    #put OpenSSL::ASN1.decode inbetween
    qer2 = OpenSSL::Timestamp::Request.new(OpenSSL::ASN1.decode(req.to_der))
    assert_equal(1, qer2.version)
    assert_equal("SHA1", qer2.algorithm)
    assert_equal(digest, qer2.message_imprint)
    assert_equal("1.2.3.4.5", qer2.policy_id)
    assert_equal(42, qer2.nonce)
  end

  def test_response_constants
    assert_equal(0, OpenSSL::Timestamp::Response::GRANTED)
    assert_equal(1, OpenSSL::Timestamp::Response::GRANTED_WITH_MODS)
    assert_equal(2, OpenSSL::Timestamp::Response::REJECTION)
    assert_equal(3, OpenSSL::Timestamp::Response::WAITING)
    assert_equal(4, OpenSSL::Timestamp::Response::REVOCATION_WARNING)
    assert_equal(5, OpenSSL::Timestamp::Response::REVOCATION_NOTIFICATION)
  end

  def test_response_creation
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.policy_id = "1.2.3.4.5"

    fac = OpenSSL::Timestamp::Factory.new
    time = Time.now
    fac.gen_time = time
    fac.serial_number = 1

    resp = fac.create_timestamp(ee_key, ts_cert_ee, req)
    assert_equal(OpenSSL::Timestamp::Response::GRANTED, resp.status)
    assert_nil(resp.failure_info)
    assert_nil(resp.status_text)
    assert_equal(1, resp.version)
    assert_equal("1.2.3.4.5", resp.policy_id)
    assert_equal("SHA1", resp.algorithm)
    assert_equal(digest, resp.message_imprint)
    assert_equal(1, resp.serial_number)
    assert_equal(time.to_i, resp.gen_time.to_i)
    assert_equal(false, resp.ordering)
    assert_nil(req.nonce)
    assert_cert(ts_cert_ee, resp.tsa_certificate)
    #compare PKCS7
    pkcs7 = OpenSSL::ASN1.decode(resp.to_der).value[1]
    assert_equal(pkcs7.to_der, resp.pkcs7.to_der)
  end

  def test_response_mandatory_fields
    fac = OpenSSL::Timestamp::Factory.new
    req = OpenSSL::Timestamp::Request.new
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      fac.create_timestamp(ee_key, ts_cert_ee, req)
    end
    req.algorithm = "sha1"
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      fac.create_timestamp(ee_key, ts_cert_ee, req)
    end
    req.message_imprint = OpenSSL::Digest::SHA1.new.digest("data")
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      fac.create_timestamp(ee_key, ts_cert_ee, req)
    end
    fac.gen_time = Time.now
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      fac.create_timestamp(ee_key, ts_cert_ee, req)
    end
    fac.serial_number = 1
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      fac.create_timestamp(ee_key, ts_cert_ee, req)
    end
    fac.default_policy_id = "1.2.3.4.5"
    fac.create_timestamp(ee_key, ts_cert_ee, req)
    fac.default_policy_id = nil
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      fac.create_timestamp(ee_key, ts_cert_ee, req)
    end
    req.policy_id = "1.2.3.4.5"
    fac.create_timestamp(ee_key, ts_cert_ee, req)
  end

  def test_response_default_policy
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest

    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    fac.default_policy_id = "1.2.3.4.6"

    resp = fac.create_timestamp(ee_key, ts_cert_ee, req)
    assert_equal(OpenSSL::Timestamp::Response::GRANTED, resp.status)
    assert_equal("1.2.3.4.6", resp.policy_id)
  end

  def test_no_cert_requested
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.cert_requested = false

    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    fac.default_policy_id = "1.2.3.4.5"

    resp = fac.create_timestamp(ee_key, ts_cert_ee, req)
    assert_equal(OpenSSL::Timestamp::Response::GRANTED, resp.status)
    assert_nil(resp.tsa_certificate)
  end

  def test_response_no_policy_defined
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      req = OpenSSL::Timestamp::Request.new
      req.algorithm = "SHA1"
      digest = OpenSSL::Digest::SHA1.new.digest("test")
      req.message_imprint = digest

      fac = OpenSSL::Timestamp::Factory.new
      fac.gen_time = Time.now
      fac.serial_number = 1

      fac.create_timestamp(ee_key, ts_cert_ee, req)
    end
  end

  def test_verify_ee_no_req
    assert_raises(TypeError) do
      ts, req = timestamp_ee
      ts.verify(nil, ca_cert)
    end
  end

  def test_verify_ee_no_root
    assert_raises(TypeError) do
      ts, req = timestamp_ee
      ts.verify(req, nil)
    end
  end

  def test_verify_ee_wrong_root_no_intermediate
    assert_raises(OpenSSL::Timestamp::CertificateValidationError) do
      ts, req = timestamp_ee
      ts.verify(req, [intermediate_cert])
    end
  end

  def test_verify_ee_wrong_root_wrong_intermediate
    assert_raises(OpenSSL::Timestamp::CertificateValidationError) do
      ts, req = timestamp_ee
      ts.verify(req, [intermediate_cert], ca_cert)
    end
  end

  def test_verify_ee_nonce_mismatch
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      ts, req = timestamp_ee
      req.nonce = 1
      ts.verify(req, [ca_cert], intermediate_cert)
    end
  end

  def test_verify_ee_intermediate_missing
    assert_raises(OpenSSL::Timestamp::CertificateValidationError) do
      ts, req = timestamp_ee
      ts.verify(req, [ca_cert])
    end
  end

  def test_verify_ee_intermediate
    ts, req = timestamp_ee
    ts.verify(req, [ca_cert], intermediate_cert)
  end

  def test_verify_ee_single_root
    ts, req = timestamp_ee
    ts.verify(req, ca_cert, intermediate_cert)
  end

  def test_verify_ee_root_from_string
    ts, req = timestamp_ee
    pem_root = ca_cert.to_pem
    ts.verify(req, pem_root, intermediate_cert)
  end

  def test_verify_ee_root_from_file
    begin
      ts, req = timestamp_ee
      File.open('root_ca', 'wb') do |file|
        file.print(ca_cert.to_pem)
      end
      ts.verify(req, File.open('root_ca', 'rb'), intermediate_cert)
    ensure
      if File.exists?('root_ca')
          File.delete('root_ca')
      end
    end
  end

  def test_verify_ee_def_policy
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.nonce = 42

    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    fac.default_policy_id = "1.2.3.4.5"

    ts = fac.create_timestamp(ee_key, ts_cert_ee, req)
    ts.verify(req, [ca_cert], intermediate_cert)
  end

  def test_verify_direct
    ts, req = timestamp_direct
    ts.verify(req, [ca_cert])
  end

  def test_verify_direct_redundant_untrusted
    ts, req = timestamp_direct
    ts.verify(req, [ca_cert], ts.tsa_certificate, ts.tsa_certificate)
  end

  def test_verify_direct_unrelated_untrusted
    ts, req = timestamp_direct
    ts.verify(req, [ca_cert], intermediate_cert)
  end

  def test_verify_direct_wrong_root
    assert_raises(OpenSSL::Timestamp::CertificateValidationError) do
      ts, req = timestamp_direct
      ts.verify(req, [intermediate_cert])
    end
  end

  def test_verify_direct_no_cert_no_intermediate
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      ts, req = timestamp_direct_no_cert
      ts.verify(req, [ca_cert])
    end
  end

  def test_verify_ee_no_cert
    ts, req = timestamp_ee_no_cert
    ts.verify(req, [ca_cert], ts_cert_ee, intermediate_cert)
  end

  def test_verify_ee_no_cert_no_intermediate
    assert_raises(OpenSSL::Timestamp::CertificateValidationError) do
      ts, req = timestamp_ee_no_cert
      ts.verify(req, [ca_cert], ts_cert_ee)
    end
  end

  def test_verity_ee_wrong_purpose
    assert_raises(OpenSSL::Timestamp::TimestampError) do
      req = OpenSSL::Timestamp::Request.new
      req.algorithm = "SHA1"
      digest = OpenSSL::Digest::SHA1.new.digest("test")
      req.message_imprint = digest
      req.policy_id = "1.2.3.4.5"
      req.nonce = 42

      fac = OpenSSL::Timestamp::Factory.new
      fac.gen_time = Time.now
      fac.serial_number = 1
      ts = fac.create_timestamp(ee_key, intermediate_cert, req)

      ts.verify(req, [ca_cert])
    end
  end

  def test_verify_ee_additional_certs_array
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.policy_id = "1.2.3.4.5"
    req.nonce = 42
    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    fac.additional_certs = [intermediate_cert]
    ts = fac.create_timestamp(ee_key, ts_cert_ee, req)
    assert_equal(2, ts.pkcs7.certificates.size)
    fac.additional_certs = nil
    ts.verify(req, ca_cert)
    ts = fac.create_timestamp(ee_key, ts_cert_ee, req)
    assert_equal(1, ts.pkcs7.certificates.size)
  end

  def test_verify_ee_additional_certs_single
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.policy_id = "1.2.3.4.5"
    req.nonce = 42
    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    fac.additional_certs = intermediate_cert
    ts = fac.create_timestamp(ee_key, ts_cert_ee, req)
    assert_equal(2, ts.pkcs7.certificates.size)
    ts.verify(req, ca_cert)
  end

  def test_verify_ee_additional_certs_with_root
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.policy_id = "1.2.3.4.5"
    req.nonce = 42
    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    fac.additional_certs = [intermediate_cert, ca_cert]
    ts = fac.create_timestamp(ee_key, ts_cert_ee, req)
    assert_equal(3, ts.pkcs7.certificates.size)
    ts.verify(req, ca_cert)
  end

  def test_verify_ee_cert_inclusion_not_requested
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.nonce = 42
    req.cert_requested = false
    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    #needed because the Request contained no policy identifier
    fac.default_policy_id = '1.2.3.4.5'
    fac.additional_certs = [ ts_cert_ee, intermediate_cert ]
    ts = fac.create_timestamp(ee_key, ts_cert_ee, req)
    assert_nil(ts.pkcs7.certificates) #since cert_requested? == false
    ts.verify(req, ca_cert, ts_cert_ee, intermediate_cert)
  end

  def test_reusable
    #test if req and faq are reusable, i.e. the internal
    #CTX_free methods don't mess up e.g. the certificates
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.policy_id = "1.2.3.4.5"
    req.nonce = 42

    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    fac.additional_certs = [ intermediate_cert ]
    ts1 = fac.create_timestamp(ee_key, ts_cert_ee, req)
    ts1.verify(req, ca_cert)
    ts2 = fac.create_timestamp(ee_key, ts_cert_ee, req)
    ts2.verify(req, ca_cert)
    refute_nil(ts1.tsa_certificate)
    refute_nil(ts2.tsa_certificate)
  end

  private

  def assert_cert expected, actual
    assert_equal expected.to_der, actual.to_der
  end

  def timestamp_ee
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.policy_id = "1.2.3.4.5"
    req.nonce = 42

    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    return fac.create_timestamp(ee_key, ts_cert_ee, req), req
  end

  def timestamp_ee_no_cert
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.policy_id = "1.2.3.4.5"
    req.nonce = 42
    req.cert_requested = false

    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    return fac.create_timestamp(ee_key, ts_cert_ee, req), req
  end

  def timestamp_direct
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.policy_id = "1.2.3.4.5"
    req.nonce = 42

    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    return fac.create_timestamp(ee_key, ts_cert_direct, req), req
  end

  def timestamp_direct_no_cert
    req = OpenSSL::Timestamp::Request.new
    req.algorithm = "SHA1"
    digest = OpenSSL::Digest::SHA1.new.digest("test")
    req.message_imprint = digest
    req.policy_id = "1.2.3.4.5"
    req.nonce = 42
    req.cert_requested = false

    fac = OpenSSL::Timestamp::Factory.new
    fac.gen_time = Time.now
    fac.serial_number = 1
    return fac.create_timestamp(ee_key, ts_cert_direct, req), req
  end
end

end
