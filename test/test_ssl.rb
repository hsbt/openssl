# frozen_string_literal: false
require_relative "utils"

if defined?(OpenSSL)

class OpenSSL::TestSSL < OpenSSL::SSLTestCase
  def test_ctx_options
    ctx = OpenSSL::SSL::SSLContext.new

    assert (OpenSSL::SSL::OP_ALL & ctx.options) == OpenSSL::SSL::OP_ALL,
           "OP_ALL is set by default"
    ctx.options = 4
    assert_equal 4, ctx.options & 4
    if ctx.options != 4
      pend "SSL_CTX_set_options() seems to be modified by distributor"
    end
    ctx.options = nil
    assert_equal OpenSSL::SSL::OP_ALL, ctx.options

    assert_equal true, ctx.setup
    assert_predicate ctx, :frozen?
    assert_equal nil, ctx.setup
  end

  def test_ssl_with_server_cert
    ctx_proc = -> ctx {
      ctx.cert = @svr_cert
      ctx.key = @svr_key
      ctx.extra_chain_cert = [@ca_cert]
    }
    server_proc = -> (ctx, ssl) {
      assert_equal @svr_cert.to_der, ssl.cert.to_der
      assert_equal nil, ssl.peer_cert

      readwrite_loop(ctx, ssl)
    }
    start_server(ctx_proc: ctx_proc, server_proc: server_proc) { |port|
      begin
        sock = TCPSocket.new("127.0.0.1", port)
        ctx = OpenSSL::SSL::SSLContext.new
        ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        ssl.connect

        assert_equal sock, ssl.io
        assert_equal nil, ssl.cert
        assert_equal @svr_cert.to_der, ssl.peer_cert.to_der
        assert_equal 2, ssl.peer_cert_chain.size
        assert_equal @svr_cert.to_der, ssl.peer_cert_chain[0].to_der
        assert_equal @ca_cert.to_der, ssl.peer_cert_chain[1].to_der
      ensure
        ssl&.close
        sock&.close
      end
    }
  end

  def test_sysread_and_syswrite
    start_server { |port|
      server_connect(port) { |ssl|
        str = "x" * 100 + "\n"
        ssl.syswrite(str)
        newstr = ssl.sysread(str.bytesize)
        assert_equal(str, newstr)

        buf = ""
        ssl.syswrite(str)
        assert_same buf, ssl.sysread(str.size, buf)
        assert_equal(str, buf)
      }
    }
  end

  def test_sync_close
    start_server { |port|
      begin
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.connect
        ssl.close
        assert_not_predicate sock, :closed?
      ensure
        sock&.close
      end

      begin
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.sync_close = true  # !!
        ssl.connect
        ssl.close
        assert_predicate sock, :closed?
      ensure
        sock&.close
      end
    }
  end

  def test_copy_stream
    start_server do |port|
      server_connect(port) do |ssl|
        IO.pipe do |r, w|
          str = "hello world\n"
          w.write(str)
          IO.copy_stream(r, ssl, str.bytesize)
          IO.copy_stream(ssl, w, str.bytesize)
          assert_equal str, r.read(str.bytesize)
        end
      end
    end
  end

  def test_client_auth_failure
    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(verify_mode: vflag, ignore_listener_error: true) { |port|
      assert_handshake_error {
        server_connect(port) { |ssl| ssl.puts("abc"); ssl.gets }
      }
    }
  end

  def test_client_auth_success
    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(verify_mode: vflag) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.key = @cli_key
      ctx.cert = @cli_cert

      server_connect(port, ctx) { |ssl|
        ssl.puts("foo")
        assert_equal("foo\n", ssl.gets)
      }

      called = nil
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.client_cert_cb = Proc.new{ |sslconn|
        called = true
        [@cli_cert, @cli_key]
      }

      server_connect(port, ctx) { |ssl|
        assert(called)
        ssl.puts("foo")
        assert_equal("foo\n", ssl.gets)
      }
    }
  end

  def test_client_auth_public_key
    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(verify_mode: vflag, ignore_listener_error: true) do |port|
      assert_raise(ArgumentError) {
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.key = @cli_key.public_key
        ctx.cert = @cli_cert
        server_connect(port, ctx) { |ssl| ssl.puts("abc"); ssl.gets }
      }

      ctx = OpenSSL::SSL::SSLContext.new
      ctx.client_cert_cb = Proc.new{ |ssl|
        [@cli_cert, @cli_key.public_key]
      }
      assert_handshake_error {
        server_connect(port, ctx) { |ssl| ssl.puts("abc"); ssl.gets }
      }
    end
  end

  def test_client_ca
    ctx_proc = Proc.new do |ctx|
      ctx.client_ca = [@ca_cert]
    end

    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(verify_mode: vflag, ctx_proc: ctx_proc) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      client_ca_from_server = nil
      ctx.client_cert_cb = Proc.new do |sslconn|
        client_ca_from_server = sslconn.client_ca
        [@cli_cert, @cli_key]
      end
      server_connect(port, ctx) { |ssl| assert_equal([@ca], client_ca_from_server) }
    }
  end

  def test_read_nonblock_without_session
    EnvUtil.suppress_warning do
      start_server(start_immediately: false) { |port|
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.sync_close = true

        assert_equal :wait_readable, ssl.read_nonblock(100, exception: false)
        ssl.write("abc\n")
        IO.select [ssl]
        assert_equal('a', ssl.read_nonblock(1))
        assert_equal("bc\n", ssl.read_nonblock(100))
        assert_equal :wait_readable, ssl.read_nonblock(100, exception: false)
        ssl.close
      }
    end
  end

  def test_starttls
    server_proc = -> (ctx, ssl) {
      while line = ssl.gets
        if line =~ /^STARTTLS$/
          ssl.write("x")
          ssl.flush
          ssl.accept
          break
        end
        ssl.write(line)
      end
      readwrite_loop(ctx, ssl)
    }

    EnvUtil.suppress_warning do # read/write on not started session
      start_server(start_immediately: false,
                   server_proc: server_proc) { |port|
        begin
          sock = TCPSocket.new("127.0.0.1", port)
          ssl = OpenSSL::SSL::SSLSocket.new(sock)

          ssl.puts "plaintext"
          assert_equal "plaintext\n", ssl.gets

          ssl.puts("STARTTLS")
          ssl.read(1)
          ssl.connect

          ssl.puts "over-tls"
          assert_equal "over-tls\n", ssl.gets
        ensure
          ssl&.close
          sock&.close
        end
      }
    end
  end

  def test_parallel
    start_server { |port|
      ssls = []
      10.times{
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.connect
        ssl.sync_close = true
        ssls << ssl
      }
      str = "x" * 1000 + "\n"
      ITERATIONS.times{
        ssls.each{|ssl|
          ssl.puts(str)
          assert_equal(str, ssl.gets)
        }
      }
      ssls.each{|ssl| ssl.close }
    }
  end

  def test_verify_result
    start_server(ignore_listener_error: true) { |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
        assert_equal(OpenSSL::X509::V_ERR_SELF_SIGNED_CERT_IN_CHAIN, ssl.verify_result)
      ensure
        ssl.close
      end
    }

    start_server { |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.verify_callback = Proc.new do |preverify_ok, store_ctx|
        store_ctx.error = OpenSSL::X509::V_OK
        true
      end
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        ssl.connect
        assert_equal(OpenSSL::X509::V_OK, ssl.verify_result)
      ensure
        ssl.close
      end
    }

    start_server(ignore_listener_error: true) { |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.verify_callback = Proc.new do |preverify_ok, store_ctx|
        store_ctx.error = OpenSSL::X509::V_ERR_APPLICATION_VERIFICATION
        false
      end
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
        assert_equal(OpenSSL::X509::V_ERR_APPLICATION_VERIFICATION, ssl.verify_result)
      ensure
        ssl.close
      end
    }
  end

  def test_exception_in_verify_callback_is_ignored
    start_server(ignore_listener_error: true) { |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.verify_callback = Proc.new do |preverify_ok, store_ctx|
        store_ctx.error = OpenSSL::X509::V_OK
        raise RuntimeError
      end
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        EnvUtil.suppress_warning do
          # SSLError, not RuntimeError
          assert_raise(OpenSSL::SSL::SSLError) { ssl.connect }
        end
        assert_equal(OpenSSL::X509::V_ERR_CERT_REJECTED, ssl.verify_result)
      ensure
        ssl.close
      end
    }
  end

  def test_sslctx_set_params
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.set_params

    assert_equal OpenSSL::SSL::VERIFY_PEER, ctx.verify_mode
    ciphers_names = ctx.ciphers.collect{|v, _, _, _| v }
    assert ciphers_names.all?{|v| /A(EC)?DH/ !~ v }, "anon ciphers are disabled"
    assert ciphers_names.all?{|v| /(RC4|MD5|EXP|DES(?!-EDE|-CBC3))/ !~ v }, "weak ciphers are disabled"
    assert_equal 0, ctx.options & OpenSSL::SSL::OP_DONT_INSERT_EMPTY_FRAGMENTS
    assert_equal OpenSSL::SSL::OP_NO_COMPRESSION,
                 ctx.options & OpenSSL::SSL::OP_NO_COMPRESSION
  end

  def test_post_connect_check_with_anon_ciphers
    pend "TLS 1.2 is not supported" unless tls12_supported?

    ctx_proc = -> ctx {
      ctx.ssl_version = :TLSv1_2
      ctx.ciphers = "aNULL"
      ctx.security_level = 0
    }

    start_server(ctx_proc: ctx_proc) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ssl_version = :TLSv1_2
      ctx.ciphers = "aNULL"
      ctx.security_level = 0
      server_connect(port, ctx) { |ssl|
        assert_raise_with_message(OpenSSL::SSL::SSLError, /anonymous cipher suite/i) {
          ssl.post_connection_check("localhost.localdomain")
        }
      }
    }
  end

  def test_post_connection_check
    sslerr = OpenSSL::SSL::SSLError

    start_server { |port|
      server_connect(port) { |ssl|
        assert_raise(sslerr){ssl.post_connection_check("localhost.localdomain")}
        assert_raise(sslerr){ssl.post_connection_check("127.0.0.1")}
        assert(ssl.post_connection_check("localhost"))
        assert_raise(sslerr){ssl.post_connection_check("foo.example.com")}

        cert = ssl.peer_cert
        assert(!OpenSSL::SSL.verify_certificate_identity(cert, "localhost.localdomain"))
        assert(!OpenSSL::SSL.verify_certificate_identity(cert, "127.0.0.1"))
        assert(OpenSSL::SSL.verify_certificate_identity(cert, "localhost"))
        assert(!OpenSSL::SSL.verify_certificate_identity(cert, "foo.example.com"))
      }
    }

    exts = [
      ["keyUsage","keyEncipherment,digitalSignature",true],
      ["subjectAltName","DNS:localhost.localdomain",false],
      ["subjectAltName","IP:127.0.0.1",false],
    ]
    @svr_cert = issue_cert(@svr, @svr_key, 4, exts, @ca_cert, @ca_key)
    start_server { |port|
      server_connect(port) { |ssl|
        assert(ssl.post_connection_check("localhost.localdomain"))
        assert(ssl.post_connection_check("127.0.0.1"))
        assert_raise(sslerr){ssl.post_connection_check("localhost")}
        assert_raise(sslerr){ssl.post_connection_check("foo.example.com")}

        cert = ssl.peer_cert
        assert(OpenSSL::SSL.verify_certificate_identity(cert, "localhost.localdomain"))
        assert(OpenSSL::SSL.verify_certificate_identity(cert, "127.0.0.1"))
        assert(!OpenSSL::SSL.verify_certificate_identity(cert, "localhost"))
        assert(!OpenSSL::SSL.verify_certificate_identity(cert, "foo.example.com"))
      }
    }

    exts = [
      ["keyUsage","keyEncipherment,digitalSignature",true],
      ["subjectAltName","DNS:*.localdomain",false],
    ]
    @svr_cert = issue_cert(@svr, @svr_key, 5, exts, @ca_cert, @ca_key)
    start_server { |port|
      server_connect(port) { |ssl|
        assert(ssl.post_connection_check("localhost.localdomain"))
        assert_raise(sslerr){ssl.post_connection_check("127.0.0.1")}
        assert_raise(sslerr){ssl.post_connection_check("localhost")}
        assert_raise(sslerr){ssl.post_connection_check("foo.example.com")}
        cert = ssl.peer_cert
        assert(OpenSSL::SSL.verify_certificate_identity(cert, "localhost.localdomain"))
        assert(!OpenSSL::SSL.verify_certificate_identity(cert, "127.0.0.1"))
        assert(!OpenSSL::SSL.verify_certificate_identity(cert, "localhost"))
        assert(!OpenSSL::SSL.verify_certificate_identity(cert, "foo.example.com"))
      }
    }
  end

  def test_verify_certificate_identity
    [true, false].each do |criticality|
      cert = create_null_byte_SAN_certificate(criticality)
      assert_equal(false, OpenSSL::SSL.verify_certificate_identity(cert, 'www.example.com'))
      assert_equal(true,  OpenSSL::SSL.verify_certificate_identity(cert, "www.example.com\0.evil.com"))
      assert_equal(false, OpenSSL::SSL.verify_certificate_identity(cert, '192.168.7.255'))
      assert_equal(true,  OpenSSL::SSL.verify_certificate_identity(cert, '192.168.7.1'))
      assert_equal(false, OpenSSL::SSL.verify_certificate_identity(cert, '13::17'))
      assert_equal(true,  OpenSSL::SSL.verify_certificate_identity(cert, '13:0:0:0:0:0:0:17'))
    end
  end

  def test_verify_hostname
    assert_equal(true,  OpenSSL::SSL.verify_hostname("www.example.com", "*.example.com"))
    assert_equal(false, OpenSSL::SSL.verify_hostname("www.subdomain.example.com", "*.example.com"))
  end

  def test_verify_wildcard
    assert_equal(false, OpenSSL::SSL.verify_wildcard("foo", "x*"))
    assert_equal(true,  OpenSSL::SSL.verify_wildcard("foo", "foo"))
    assert_equal(true,  OpenSSL::SSL.verify_wildcard("foo", "f*"))
    assert_equal(true,  OpenSSL::SSL.verify_wildcard("foo", "*"))
    assert_equal(false, OpenSSL::SSL.verify_wildcard("abc*bcd", "abcd"))
    assert_equal(false, OpenSSL::SSL.verify_wildcard("xn--qdk4b9b", "x*"))
    assert_equal(false, OpenSSL::SSL.verify_wildcard("xn--qdk4b9b", "*--qdk4b9b"))
    assert_equal(true,  OpenSSL::SSL.verify_wildcard("xn--qdk4b9b", "xn--qdk4b9b"))
  end

  # Comments in this test is excerpted from http://tools.ietf.org/html/rfc6125#page-27
  def test_post_connection_check_wildcard_san
    # case-insensitive ASCII comparison
    # RFC 6125, section 6.4.1
    #
    # "..matching of the reference identifier against the presented identifier
    # is performed by comparing the set of domain name labels using a
    # case-insensitive ASCII comparison, as clarified by [DNS-CASE] (e.g.,
    # "WWW.Example.Com" would be lower-cased to "www.example.com" for
    # comparison purposes)
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*.example.com'), 'www.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*.Example.COM'), 'www.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*.example.com'), 'WWW.Example.COM'))
    # 1.  The client SHOULD NOT attempt to match a presented identifier in
    #     which the wildcard character comprises a label other than the
    #     left-most label (e.g., do not match bar.*.example.net).
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:www.*.com'), 'www.example.com'))
    # 2.  If the wildcard character is the only character of the left-most
    #     label in the presented identifier, the client SHOULD NOT compare
    #     against anything but the left-most label of the reference
    #     identifier (e.g., *.example.com would match foo.example.com but
    #     not bar.foo.example.com or example.com).
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*.example.com'), 'foo.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*.example.com'), 'bar.foo.example.com'))
    # 3.  The client MAY match a presented identifier in which the wildcard
    #     character is not the only character of the label (e.g.,
    #     baz*.example.net and *baz.example.net and b*z.example.net would
    #     be taken to match baz1.example.net and foobaz.example.net and
    #     buzz.example.net, respectively).  ...
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:baz*.example.com'), 'baz1.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*baz.example.com'), 'foobaz.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:b*z.example.com'), 'buzz.example.com'))
    # Section 6.4.3 of RFC6125 states that client should NOT match identifier
    # where wildcard is other than left-most label.
    #
    # Also implicitly mentions the wildcard character only in singular form,
    # and discourages matching against more than one wildcard.
    #
    # See RFC 6125, section 7.2, subitem 2.
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*b*.example.com'), 'abc.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*b*.example.com'), 'ab.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*b*.example.com'), 'bc.example.com'))
    #                                ...  However, the client SHOULD NOT
    #   attempt to match a presented identifier where the wildcard
    #   character is embedded within an A-label or U-label [IDNA-DEFS] of
    #   an internationalized domain name [IDNA-PROTO].
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:xn*.example.com'), 'xn1ca.example.com'))
    # part of A-label
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:xn--*.example.com'), 'xn--1ca.example.com'))
    # part of U-label
    # dNSName in RFC5280 is an IA5String so U-label should NOT be allowed
    # regardless of wildcard.
    #
    # See Section 7.2 of RFC 5280:
    #   IA5String is limited to the set of ASCII characters.
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:á*.example.com'), 'á1.example.com'))
  end

  def test_post_connection_check_wildcard_cn
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*.example.com'), 'www.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*.Example.COM'), 'www.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*.example.com'), 'WWW.Example.COM'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('www.*.com'), 'www.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*.example.com'), 'foo.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*.example.com'), 'bar.foo.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('baz*.example.com'), 'baz1.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*baz.example.com'), 'foobaz.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('b*z.example.com'), 'buzz.example.com'))
    # Section 6.4.3 of RFC6125 states that client should NOT match identifier
    # where wildcard is other than left-most label.
    #
    # Also implicitly mentions the wildcard character only in singular form,
    # and discourages matching against more than one wildcard.
    #
    # See RFC 6125, section 7.2, subitem 2.
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*b*.example.com'), 'abc.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*b*.example.com'), 'ab.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*b*.example.com'), 'bc.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('xn*.example.com'), 'xn1ca.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('xn--*.example.com'), 'xn--1ca.example.com'))
    # part of U-label
    # Subject in RFC5280 states case-insensitive ASCII comparison.
    #
    # See Section 7.2 of RFC 5280:
    #   IA5String is limited to the set of ASCII characters.
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('á*.example.com'), 'á1.example.com'))
  end

  def create_cert_with_san(san)
    ef = OpenSSL::X509::ExtensionFactory.new
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse("/DC=some/DC=site/CN=Some Site")
    ext = ef.create_ext('subjectAltName', san)
    cert.add_extension(ext)
    cert
  end

  def create_cert_with_name(name)
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.new([['DC', 'some'], ['DC', 'site'], ['CN', name]])
    cert
  end


  # Create NULL byte SAN certificate
  def create_null_byte_SAN_certificate(critical = false)
    ef = OpenSSL::X509::ExtensionFactory.new
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse "/DC=some/DC=site/CN=Some Site"
    ext = ef.create_ext('subjectAltName', 'DNS:placeholder,IP:192.168.7.1,IP:13::17', critical)
    ext_asn1 = OpenSSL::ASN1.decode(ext.to_der)
    san_list_der = ext_asn1.value.reduce(nil) { |memo,val| val.tag == 4 ? val.value : memo }
    san_list_asn1 = OpenSSL::ASN1.decode(san_list_der)
    san_list_asn1.value[0].value = "www.example.com\0.evil.com"
    pos = critical ? 2 : 1
    ext_asn1.value[pos].value = san_list_asn1.to_der
    real_ext = OpenSSL::X509::Extension.new ext_asn1
    cert.add_extension(real_ext)
    cert
  end

  def socketpair
    if defined? UNIXSocket
      UNIXSocket.pair
    else
      Socket.pair(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    end
  end

  def test_tlsext_hostname
    fooctx = OpenSSL::SSL::SSLContext.new
    fooctx.tmp_dh_callback = proc { Fixtures.pkey_dh("dh1024") }
    fooctx.cert = @cli_cert
    fooctx.key = @cli_key

    ctx_proc = proc { |ctx|
      ctx.servername_cb = proc { |ssl, servername|
        case servername
        when "foo.example.com"
          fooctx
        when "bar.example.com"
          nil
        else
          raise "unreachable"
        end
      }
    }
    start_server(ctx_proc: ctx_proc) do |port|
      sock = TCPSocket.new("127.0.0.1", port)
      begin
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.hostname = "foo.example.com"
        ssl.connect
        assert_equal @cli_cert.serial, ssl.peer_cert.serial
        assert_predicate fooctx, :frozen?
      ensure
        ssl&.close
        sock.close
      end

      sock = TCPSocket.new("127.0.0.1", port)
      begin
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.hostname = "bar.example.com"
        ssl.connect
        assert_equal @svr_cert.serial, ssl.peer_cert.serial
      ensure
        ssl&.close
        sock.close
      end
    end
  end

  def test_servername_cb_raises_an_exception_on_unknown_objects
    hostname = 'example.org'

    ctx2 = OpenSSL::SSL::SSLContext.new
    ctx2.cert = @svr_cert
    ctx2.key = @svr_key
    ctx2.tmp_dh_callback = proc { Fixtures.pkey_dh("dh1024") }
    ctx2.servername_cb = lambda { |args| Object.new }

    sock1, sock2 = socketpair

    s2 = OpenSSL::SSL::SSLSocket.new(sock2, ctx2)

    ctx1 = OpenSSL::SSL::SSLContext.new

    s1 = OpenSSL::SSL::SSLSocket.new(sock1, ctx1)
    s1.hostname = hostname
    t = Thread.new {
      assert_raise(OpenSSL::SSL::SSLError) do
        s1.connect
      end
    }

    assert_raise(ArgumentError) do
      s2.accept
    end

    assert t.join
  ensure
    sock1.close if sock1
    sock2.close if sock2
  end

  def test_verify_hostname_on_connect
    ctx_proc = proc { |ctx|
      exts = [
        ["keyUsage", "keyEncipherment,digitalSignature", true],
        ["subjectAltName", "DNS:a.example.com,DNS:*.b.example.com," \
                           "DNS:c*.example.com,DNS:d.*.example.com"],
      ]
      ctx.cert = issue_cert(@svr, @svr_key, 4, exts, @ca_cert, @ca_key)
      ctx.key = @svr_key
    }

    start_server(ctx_proc: ctx_proc, ignore_listener_error: true) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_hostname = true
      ctx.cert_store = OpenSSL::X509::Store.new
      ctx.cert_store.add_cert(@ca_cert)
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER

      [
        ["a.example.com", true],
        ["A.Example.Com", true],
        ["x.example.com", false],
        ["b.example.com", false],
        ["x.b.example.com", true],
        ["cx.example.com", true],
        ["d.x.example.com", false],
      ].each do |name, expected_ok|
        begin
          sock = TCPSocket.new("127.0.0.1", port)
          ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          ssl.hostname = name
          if expected_ok
            assert_nothing_raised { ssl.connect }
          else
            assert_handshake_error { ssl.connect }
          end
        ensure
          ssl.close if ssl
          sock.close if sock
        end
      end
    end
  end

  def test_connect_certificate_verify_failed_exception_message
    start_server(ignore_listener_error: true) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      assert_raise_with_message(OpenSSL::SSL::SSLError, /self signed/) {
        server_connect(port, ctx)
      }
    }

    ctx_proc = proc { |ctx|
      ctx.cert = issue_cert(@svr, @svr_key, 30, [], @ca_cert, @ca_key,
                            not_before: Time.now-100, not_after: Time.now-10)
    }
    start_server(ignore_listener_error: true, ctx_proc: ctx_proc) { |port|
      store = OpenSSL::X509::Store.new
      store.add_cert(@ca_cert)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(cert_store: store)
      assert_raise_with_message(OpenSSL::SSL::SSLError, /expired/) {
        server_connect(port, ctx)
      }
    }
  end

  def test_unset_OP_ALL
    ctx_proc = Proc.new { |ctx|
      # If OP_DONT_INSERT_EMPTY_FRAGMENTS is not defined, this test is
      # redundant because the default options already are equal to OP_ALL.
      # But it also degrades gracefully, so keep it
      ctx.options = OpenSSL::SSL::OP_ALL
    }
    start_server(ctx_proc: ctx_proc) { |port|
      server_connect(port) { |ssl|
        ssl.puts('hello')
        assert_equal("hello\n", ssl.gets)
      }
    }
  end

  def check_supported_protocol_versions
    possible_versions = [
      OpenSSL::SSL::SSL3_VERSION,
      OpenSSL::SSL::TLS1_VERSION,
      OpenSSL::SSL::TLS1_1_VERSION,
      OpenSSL::SSL::TLS1_2_VERSION,
      # OpenSSL 1.1.1
      defined?(OpenSSL::SSL::TLS1_3_VERSION) && OpenSSL::SSL::TLS1_3_VERSION,
    ].compact

    # Prepare for testing & do sanity check
    supported = []
    possible_versions.each do |ver|
      catch(:unsupported) {
        ctx_proc = proc { |ctx|
          begin
            ctx.min_version = ctx.max_version = ver
          rescue ArgumentError, OpenSSL::SSL::SSLError
            throw :unsupported
          end
        }
        start_server(ctx_proc: ctx_proc, ignore_listener_error: true) do |port|
          begin
            server_connect(port) { }
          rescue OpenSSL::SSL::SSLError, Errno::ECONNRESET
          else
            supported << ver
          end
        end
      }
    end
    assert_not_empty supported

    supported
  end

  def test_set_params_min_version
    supported = check_supported_protocol_versions
    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)

    if supported.include?(OpenSSL::SSL::SSL3_VERSION)
      # SSLContext#set_params properly disables SSL 3.0 by default
      ctx_proc = proc { |ctx|
        ctx.min_version = ctx.max_version = OpenSSL::SSL::SSL3_VERSION
      }
      start_server(ctx_proc: ctx_proc, ignore_listener_error: true) { |port|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.set_params(cert_store: store, verify_hostname: false)
        assert_handshake_error { server_connect(port, ctx) { } }
      }
    end
  end

  def test_minmax_version
    supported = check_supported_protocol_versions

    # name: The string that would be returned by SSL_get_version()
    # method: The version-specific method name (if any)
    vmap = {
      OpenSSL::SSL::SSL3_VERSION => { name: "SSLv3", method: "SSLv3" },
      OpenSSL::SSL::SSL3_VERSION => { name: "SSLv3", method: "SSLv3" },
      OpenSSL::SSL::TLS1_VERSION => { name: "TLSv1", method: "TLSv1" },
      OpenSSL::SSL::TLS1_1_VERSION => { name: "TLSv1.1", method: "TLSv1_1" },
      OpenSSL::SSL::TLS1_2_VERSION => { name: "TLSv1.2", method: "TLSv1_2" },
      # OpenSSL 1.1.1
      defined?(OpenSSL::SSL::TLS1_3_VERSION) && OpenSSL::SSL::TLS1_3_VERSION =>
      { name: "TLSv1.3", method: nil },
    }

    # Server enables a single version
    supported.each do |ver|
      ctx_proc = proc { |ctx| ctx.min_version = ctx.max_version = ver }
      start_server(ctx_proc: ctx_proc, ignore_listener_error: true) { |port|
        supported.each do |cver|
          # Client enables a single version
          ctx1 = OpenSSL::SSL::SSLContext.new
          ctx1.min_version = ctx1.max_version = cver
          if ver == cver
            server_connect(port, ctx1) { |ssl|
              assert_equal vmap[cver][:name], ssl.ssl_version
            }
          else
            assert_handshake_error { server_connect(port, ctx1) { } }
          end

          # There is no version-specific SSL methods for TLS 1.3
          if cver <= OpenSSL::SSL::TLS1_2_VERSION
            # Client enables a single version using #ssl_version=
            ctx2 = OpenSSL::SSL::SSLContext.new
            ctx2.ssl_version = vmap[cver][:method]
            if ver == cver
              server_connect(port, ctx2) { |ssl|
                assert_equal vmap[cver][:name], ssl.ssl_version
              }
            else
              assert_handshake_error { server_connect(port, ctx2) { } }
            end
          end
        end

        # Client enables all supported versions
        ctx3 = OpenSSL::SSL::SSLContext.new
        ctx3.min_version = ctx3.max_version = nil
        server_connect(port, ctx3) { |ssl|
          assert_equal vmap[ver][:name], ssl.ssl_version
        }
      }
    end

    if supported.size == 1
      pend "More than one protocol version must be supported"
    end

    # Server sets min_version (earliest is disabled)
    sver = supported[1]
    ctx_proc = proc { |ctx| ctx.min_version = sver }
    start_server(ctx_proc: ctx_proc, ignore_listener_error: true) { |port|
      supported.each do |cver|
        # Client sets min_version
        ctx1 = OpenSSL::SSL::SSLContext.new
        ctx1.min_version = cver
        server_connect(port, ctx1) { |ssl|
          assert_equal vmap[supported.last][:name], ssl.ssl_version
        }

        # Client sets max_version
        ctx2 = OpenSSL::SSL::SSLContext.new
        ctx2.max_version = cver
        if cver >= sver
          server_connect(port, ctx2) { |ssl|
            assert_equal vmap[cver][:name], ssl.ssl_version
          }
        else
          assert_handshake_error { server_connect(port, ctx2) { } }
        end
      end
    }

    # Server sets max_version (latest is disabled)
    sver = supported[-2]
    ctx_proc = proc { |ctx| ctx.max_version = sver }
    start_server(ctx_proc: ctx_proc, ignore_listener_error: true) { |port|
      supported.each do |cver|
        # Client sets min_version
        ctx1 = OpenSSL::SSL::SSLContext.new
        ctx1.min_version = cver
        if cver <= sver
          server_connect(port, ctx1) { |ssl|
            assert_equal vmap[sver][:name], ssl.ssl_version
          }
        else
          assert_handshake_error { server_connect(port, ctx1) { } }
        end

        # Client sets max_version
        ctx2 = OpenSSL::SSL::SSLContext.new
        ctx2.max_version = cver
        server_connect(port, ctx2) { |ssl|
          if cver >= sver
            assert_equal vmap[sver][:name], ssl.ssl_version
          else
            assert_equal vmap[cver][:name], ssl.ssl_version
          end
        }
      end
    }
  end

  def test_options_disable_versions
    # Note: Use of these OP_* flags has been deprecated since OpenSSL 1.1.0.
    supported = check_supported_protocol_versions

    if supported.include?(OpenSSL::SSL::TLS1_1_VERSION) &&
        supported.include?(OpenSSL::SSL::TLS1_2_VERSION)
      # Server disables ~ TLS 1.1
      ctx_proc = proc { |ctx|
        ctx.options |= OpenSSL::SSL::OP_NO_SSLv2 | OpenSSL::SSL::OP_NO_SSLv3 |
          OpenSSL::SSL::OP_NO_TLSv1 | OpenSSL::SSL::OP_NO_TLSv1_1
      }
      start_server(ctx_proc: ctx_proc, ignore_listener_error: true) { |port|
        # Client only supports TLS 1.1
        ctx1 = OpenSSL::SSL::SSLContext.new
        ctx1.min_version = ctx1.max_version = OpenSSL::SSL::TLS1_1_VERSION
        assert_handshake_error { server_connect(port, ctx1) { } }

        # Client only supports TLS 1.2
        ctx2 = OpenSSL::SSL::SSLContext.new
        ctx2.min_version = ctx2.max_version = OpenSSL::SSL::TLS1_2_VERSION
        assert_nothing_raised { server_connect(port, ctx2) { } }
      }

      # Server only supports TLS 1.1
      ctx_proc = proc { |ctx|
        ctx.min_version = ctx.max_version = OpenSSL::SSL::TLS1_1_VERSION
      }
      start_server(ctx_proc: ctx_proc, ignore_listener_error: true) { |port|
        # Client disables TLS 1.1
        ctx1 = OpenSSL::SSL::SSLContext.new
        ctx1.options |= OpenSSL::SSL::OP_NO_TLSv1_1
        assert_handshake_error { server_connect(port, ctx1) { } }

        # Client disables TLS 1.2
        ctx2 = OpenSSL::SSL::SSLContext.new
        ctx2.options |= OpenSSL::SSL::OP_NO_TLSv1_2
        assert_nothing_raised { server_connect(port, ctx2) { } }
      }
    else
      pend "TLS 1.1 and TLS 1.2 must be supported; skipping"
    end
  end

  def test_ssl_methods_constant
    EnvUtil.suppress_warning { # Deprecated in v2.1.0
      base = [:TLSv1_2, :TLSv1_1, :TLSv1, :SSLv3, :SSLv2, :SSLv23]
      base.each do |name|
        assert_include OpenSSL::SSL::SSLContext::METHODS, name
        assert_include OpenSSL::SSL::SSLContext::METHODS, :"#{name}_client"
        assert_include OpenSSL::SSL::SSLContext::METHODS, :"#{name}_server"
      end
    }
  end

  def test_renegotiation_cb
    num_handshakes = 0
    renegotiation_cb = Proc.new { |ssl| num_handshakes += 1 }
    ctx_proc = Proc.new { |ctx| ctx.renegotiation_cb = renegotiation_cb }
    start_server_version(:SSLv23, ctx_proc) { |port|
      server_connect(port) { |ssl|
        assert_equal(1, num_handshakes)
      }
    }
  end

if openssl?(1, 0, 2) || libressl?
  def test_alpn_protocol_selection_ary
    advertised = ["http/1.1", "spdy/2"]
    ctx_proc = Proc.new { |ctx|
      ctx.alpn_select_cb = -> (protocols) {
        protocols.first
      }
      ctx.alpn_protocols = advertised
    }
    start_server_version(:SSLv23, ctx_proc) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.alpn_protocols = advertised
      server_connect(port, ctx) { |ssl|
        assert_equal(advertised.first, ssl.alpn_protocol)
      }
    }
  end

  def test_alpn_protocol_selection_cancel
    sock1, sock2 = socketpair

    ctx1 = OpenSSL::SSL::SSLContext.new
    ctx1.cert = @svr_cert
    ctx1.key = @svr_key
    ctx1.tmp_dh_callback = proc { Fixtures.pkey_dh("dh1024") }
    ctx1.alpn_select_cb = -> (protocols) { nil }
    ssl1 = OpenSSL::SSL::SSLSocket.new(sock1, ctx1)

    ctx2 = OpenSSL::SSL::SSLContext.new
    ctx2.alpn_protocols = ["http/1.1"]
    ssl2 = OpenSSL::SSL::SSLSocket.new(sock2, ctx2)

    t = Thread.new {
      ssl2.connect_nonblock(exception: false)
    }
    assert_raise_with_message(TypeError, /nil/) { ssl1.accept }
    t.join
  ensure
    sock1&.close
    sock2&.close
    ssl1&.close
    ssl2&.close
    t&.kill
    t&.join
  end
end

  def test_npn_protocol_selection_ary
    pend "TLS 1.2 is not supported" unless tls12_supported?
    pend "NPN is not supported" unless \
      OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)
    pend "LibreSSL 2.6 has broken NPN functions" if libressl?(2, 6, 1)

    advertised = ["http/1.1", "spdy/2"]
    ctx_proc = proc { |ctx| ctx.npn_protocols = advertised }
    start_server_version(:TLSv1_2, ctx_proc) { |port|
      selector = lambda { |which|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.npn_select_cb = -> (protocols) { protocols.send(which) }
        server_connect(port, ctx) { |ssl|
          assert_equal(advertised.send(which), ssl.npn_protocol)
        }
      }
      selector.call(:first)
      selector.call(:last)
    }
  end

  def test_npn_protocol_selection_enum
    pend "TLS 1.2 is not supported" unless tls12_supported?
    pend "NPN is not supported" unless \
      OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)
    pend "LibreSSL 2.6 has broken NPN functions" if libressl?(2, 6, 1)

    advertised = Object.new
    def advertised.each
      yield "http/1.1"
      yield "spdy/2"
    end
    ctx_proc = Proc.new { |ctx| ctx.npn_protocols = advertised }
    start_server_version(:TLSv1_2, ctx_proc) { |port|
      selector = lambda { |selected, which|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.npn_select_cb = -> (protocols) { protocols.to_a.send(which) }
        server_connect(port, ctx) { |ssl|
          assert_equal(selected, ssl.npn_protocol)
        }
      }
      selector.call("http/1.1", :first)
      selector.call("spdy/2", :last)
    }
  end

  def test_npn_protocol_selection_cancel
    pend "TLS 1.2 is not supported" unless tls12_supported?
    pend "NPN is not supported" unless \
      OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)
    pend "LibreSSL 2.6 has broken NPN functions" if libressl?(2, 6, 1)

    ctx_proc = Proc.new { |ctx| ctx.npn_protocols = ["http/1.1"] }
    start_server_version(:TLSv1_2, ctx_proc) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.npn_select_cb = -> (protocols) { raise RuntimeError.new }
      assert_raise(RuntimeError) { server_connect(port, ctx) }
    }
  end

  def test_npn_advertised_protocol_too_long
    pend "TLS 1.2 is not supported" unless tls12_supported?
    pend "NPN is not supported" unless \
      OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)
    pend "LibreSSL 2.6 has broken NPN functions" if libressl?(2, 6, 1)

    ctx_proc = Proc.new { |ctx| ctx.npn_protocols = ["a" * 256] }
    start_server_version(:TLSv1_2, ctx_proc) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.npn_select_cb = -> (protocols) { protocols.first }
      assert_handshake_error { server_connect(port, ctx) }
    }
  end

  def test_npn_selected_protocol_too_long
    pend "TLS 1.2 is not supported" unless tls12_supported?
    pend "NPN is not supported" unless \
      OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)
    pend "LibreSSL 2.6 has broken NPN functions" if libressl?(2, 6, 1)

    ctx_proc = Proc.new { |ctx| ctx.npn_protocols = ["http/1.1"] }
    start_server_version(:TLSv1_2, ctx_proc) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.npn_select_cb = -> (protocols) { "a" * 256 }
      assert_handshake_error { server_connect(port, ctx) }
    }
  end

  def test_close_after_socket_close
    server_proc = proc { |ctx, ssl|
      # Do nothing
    }
    start_server(server_proc: server_proc) { |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      ssl.connect
      sock.close
      assert_nothing_raised do
        ssl.close
      end
    }
  end

  def test_sync_close_without_connect
    Socket.open(:INET, :STREAM) {|s|
      ssl = OpenSSL::SSL::SSLSocket.new(s)
      ssl.sync_close = true
      ssl.close
      assert(s.closed?)
    }
  end

  def test_get_ephemeral_key
    # OpenSSL >= 1.0.2
    unless OpenSSL::SSL::SSLSocket.method_defined?(:tmp_key)
      pend "SSL_get_server_tmp_key() is not supported"
    end

    if tls12_supported?
      # kRSA
      ctx_proc1 = proc { |ctx|
        ctx.ssl_version = :TLSv1_2
        ctx.ciphers = "kRSA"
      }
      start_server(ctx_proc: ctx_proc1) do |port|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ssl_version = :TLSv1_2
        ctx.ciphers = "kRSA"
        server_connect(port, ctx) { |ssl| assert_nil ssl.tmp_key }
      end
    end

    if defined?(OpenSSL::PKey::DH) && tls12_supported?
      # DHE
      # TODO: How to test this with TLS 1.3?
      ctx_proc2 = proc { |ctx|
        ctx.ssl_version = :TLSv1_2
        ctx.ciphers = "EDH"
      }
      start_server(ctx_proc: ctx_proc2) do |port|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ssl_version = :TLSv1_2
        ctx.ciphers = "EDH"
        server_connect(port, ctx) { |ssl|
          assert_instance_of OpenSSL::PKey::DH, ssl.tmp_key
        }
      end
    end

    if defined?(OpenSSL::PKey::EC)
      # ECDHE
      ctx_proc3 = proc { |ctx|
        ctx.ciphers = "DEFAULT:!kRSA:!kEDH"
        ctx.ecdh_curves = "P-256"
      }
      start_server(ctx_proc: ctx_proc3) do |port|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ciphers = "DEFAULT:!kRSA:!kEDH"
        server_connect(port, ctx) { |ssl|
          assert_instance_of OpenSSL::PKey::EC, ssl.tmp_key
        }
      end
    end
  end

  def test_server_with_multiple_certificate
    ctx_proc = proc { |ctx|
      ctx.ssl_version = :TLSv1_2
      ctx.ciphers = 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384'
      ctx.keys = [@svr_key, @ec_key]
      ctx.certs = [@svr_cert, @ec_cert]
    }
    start_server(ctx_proc: ctx_proc) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ssl_version = :TLSv1_2
      ctx.ciphers = 'ECDHE-RSA-AES256-GCM-SHA384'
      server_connect(port, ctx) { |ssl|
        assert_instance_of OpenSSL::PKey::RSA, ssl.peer_cert.public_key
      }

      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ciphers = 'ECDHE-ECDSA-AES256-GCM-SHA384'
      server_connect(port, ctx) { |ssl|
        assert_instance_of OpenSSL::PKey::EC, ssl.peer_cert.public_key
      }
    end
  end

  def test_dh_callback
    pend "TLS 1.2 is not supported" unless tls12_supported?

    called = false
    ctx_proc = -> ctx {
      ctx.ssl_version = :TLSv1_2
      ctx.ciphers = "DH:!NULL"
      ctx.tmp_dh_callback = ->(*args) {
        called = true
        Fixtures.pkey_dh("dh1024")
      }
    }
    start_server(ctx_proc: ctx_proc) do |port|
      server_connect(port) { |ssl|
        assert called, "dh callback should be called"
        if ssl.respond_to?(:tmp_key)
          assert_equal Fixtures.pkey_dh("dh1024").to_der, ssl.tmp_key.to_der
        end
      }
    end
  end

  def test_connect_works_when_setting_dh_callback_to_nil
    pend "TLS 1.2 is not supported" unless tls12_supported?

    ctx_proc = -> ctx {
      ctx.ssl_version = :TLSv1_2
      ctx.ciphers = "DH:!NULL" # use DH
      ctx.tmp_dh_callback = nil
    }
    start_server(ctx_proc: ctx_proc) do |port|
      EnvUtil.suppress_warning { # uses default callback
        assert_nothing_raised {
          server_connect(port) { }
        }
      }
    end
  end

  def test_tmp_ecdh_callback
    pend "EC is disabled" unless defined?(OpenSSL::PKey::EC)
    pend "tmp_ecdh_callback is not supported" unless \
      OpenSSL::SSL::SSLContext.method_defined?(:tmp_ecdh_callback)
    pend "LibreSSL 2.6 has broken SSL_CTX_set_tmp_ecdh_callback()" \
      if libressl?(2, 6, 1)

    EnvUtil.suppress_warning do # tmp_ecdh_callback is deprecated (2016-05)
      called = false
      ctx_proc = -> ctx {
        ctx.ciphers = "DEFAULT:!kRSA:!kEDH"
        ctx.tmp_ecdh_callback = -> (*args) {
          called = true
          OpenSSL::PKey::EC.new "prime256v1"
        }
      }
      start_server(ctx_proc: ctx_proc) do |port|
        server_connect(port) { |s|
          assert called, "tmp_ecdh_callback should be called"
        }
      end
    end
  end

  def test_ecdh_curves
    pend "EC is disabled" unless defined?(OpenSSL::PKey::EC)

    ctx_proc = -> ctx {
      # Enable both ECDHE (~ TLS 1.2) cipher suites and TLS 1.3
      ctx.ciphers = "DEFAULT:!kRSA:!kEDH"
      ctx.ecdh_curves = "P-384:P-521"
    }
    start_server(ctx_proc: ctx_proc, ignore_listener_error: true) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ecdh_curves = "P-256:P-384" # disable P-521 for OpenSSL >= 1.0.2

      server_connect(port, ctx) { |ssl|
        cs = ssl.cipher[0]
        if /\ATLS/ =~ cs # Is TLS 1.3 is used?
          assert_equal "secp384r1", ssl.tmp_key.group.curve_name
        else
          assert_match (/\AECDH/), cs
          if ssl.respond_to?(:tmp_key)
            assert_equal "secp384r1", ssl.tmp_key.group.curve_name
          end
        end
      }

      if openssl?(1, 0, 2) || libressl?(2, 5, 1)
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ecdh_curves = "P-256"

        assert_raise(OpenSSL::SSL::SSLError) {
          server_connect(port, ctx) { }
        }

        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ecdh_curves = "P-521:P-384"

        server_connect(port, ctx) { |ssl|
          assert_equal "secp521r1", ssl.tmp_key.group.curve_name
        }
      end
    end
  end

  def test_security_level
    ctx = OpenSSL::SSL::SSLContext.new
    begin
      ctx.security_level = 1
    rescue NotImplementedError
      assert_equal(0, ctx.security_level)
      return
    end
    assert_equal(1, ctx.security_level)
    # assert_raise(OpenSSL::SSL::SSLError) { ctx.key = Fixtures.pkey("dsa512") }
    # ctx.key = Fixtures.pkey("rsa1024")
    # ctx.security_level = 2
    # assert_raise(OpenSSL::SSL::SSLError) { ctx.key = Fixtures.pkey("rsa1024") }
    pend "FIXME: SSLContext#key= currently does not raise because SSL_CTX_use_certificate() is delayed"
  end

  def test_dup
    ctx = OpenSSL::SSL::SSLContext.new
    sock1, sock2 = socketpair
    ssl = OpenSSL::SSL::SSLSocket.new(sock1, ctx)

    assert_raise(NoMethodError) { ctx.dup }
    assert_raise(NoMethodError) { ssl.dup }
  ensure
    ssl.close if ssl
    sock1.close
    sock2.close
  end

  def test_freeze_calls_setup
    bug = "[ruby/openssl#85]"
    start_server(ignore_listener_error: true) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.freeze
      assert_raise(OpenSSL::SSL::SSLError, bug) {
        server_connect(port, ctx)
      }
    }
  end

  private

  def start_server_version(version, ctx_proc = nil,
                           server_proc = method(:readwrite_loop), &blk)
    ctx_wrap = Proc.new { |ctx|
      ctx.ssl_version = version
      ctx_proc.call(ctx) if ctx_proc
    }
    start_server(
      ctx_proc: ctx_wrap,
      server_proc: server_proc,
      ignore_listener_error: true,
      &blk
    )
  end

  def server_connect(port, ctx = nil)
    sock = TCPSocket.new("127.0.0.1", port)
    ssl = ctx ? OpenSSL::SSL::SSLSocket.new(sock, ctx) : OpenSSL::SSL::SSLSocket.new(sock)
    ssl.sync_close = true
    ssl.connect
    yield ssl if block_given?
  ensure
    if ssl
      ssl.close
    elsif sock
      sock.close
    end
  end

  def assert_handshake_error
    # different OpenSSL versions react differently when facing a SSL/TLS version
    # that has been marked as forbidden, therefore either of these may be raised
    assert_raise(OpenSSL::SSL::SSLError, Errno::ECONNRESET) {
      yield
    }
  end
end

end
