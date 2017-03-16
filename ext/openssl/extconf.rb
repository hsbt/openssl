# -*- coding: us-ascii -*-
# frozen_string_literal: false
=begin
= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
  All rights reserved.

= Licence
  This program is licensed under the same licence as Ruby.
  (See the file 'LICENCE'.)
=end

require "mkmf"
require File.expand_path('../deprecation', __FILE__)

dir_config("openssl")
dir_config("kerberos")

Logging::message "=== OpenSSL for Ruby configurator ===\n"

# Add -Werror=deprecated-declarations to $warnflags if available
OpenSSL.deprecated_warning_flag

##
# Adds -DOSSL_DEBUG for compilation and some more targets when GCC is used
# To turn it on, use: --with-debug or --enable-debug
#
if with_config("debug") or enable_config("debug")
  $defs.push("-DOSSL_DEBUG")
end

Logging::message "=== Checking for system dependent stuff... ===\n"
have_library("nsl", "t_open")
have_library("socket", "socket")

Logging::message "=== Checking for required stuff... ===\n"
result = pkg_config("openssl") && have_header("openssl/ssl.h")
unless result
  if $mswin || $mingw
    # required for static OpenSSL libraries
    have_library("gdi32") # OpenSSL <= 1.0.2 (for RAND_screen())
    have_library("crypt32")
  end

  result = %w[crypto libeay32].any? {|lib| have_library(lib, "CRYPTO_malloc")}
  result &&= %w[ssl ssleay32].any? {|lib| have_library(lib, "SSL_new")}
  unless result
    raise "OpenSSL library could not be found. You might want to use " \
      "--with-openssl-dir=<dir> option to specify the prefix where OpenSSL " \
      "is installed."
  end
  unless have_header("openssl/ssl.h")
    raise "OpenSSL library itself was found, but the necessary header files " \
      "are missing. Installing \"development package\" of OpenSSL on your " \
      "system might help."
  end
end

unless checking_for("OpenSSL version is 1.0.1 or later") {
    try_static_assert("OPENSSL_VERSION_NUMBER >= 0x10001000L", "openssl/opensslv.h") }
  raise "OpenSSL >= 1.0.1 or LibreSSL is required"
end

Logging::message "=== Checking for OpenSSL features... ===\n"
# compile options

# SSLv2 and SSLv3 may be removed in future versions of OpenSSL, and even macros
# like OPENSSL_NO_SSL2 may not be defined.
have_func("SSLv2_method")
have_func("SSLv3_method")
have_func("RAND_egd")
engines = %w{builtin_engines openbsd_dev_crypto dynamic 4758cca aep atalla chil
             cswift nuron sureware ubsec padlock capi gmp gost cryptodev aesni}
engines.each { |name|
  OpenSSL.check_func_or_macro("ENGINE_load_#{name}", "openssl/engine.h")
}

# added in 1.0.2
have_func("EC_curve_nist2nid")
have_func("X509_REVOKED_dup")
have_func("X509_STORE_CTX_get0_store")
have_func("SSL_CTX_set_alpn_select_cb")
OpenSSL.check_func_or_macro("SSL_CTX_set1_curves_list", "openssl/ssl.h")
OpenSSL.check_func_or_macro("SSL_CTX_set_ecdh_auto", "openssl/ssl.h")
OpenSSL.check_func_or_macro("SSL_get_server_tmp_key", "openssl/ssl.h")
have_func("SSL_is_server")

# added in 1.1.0
have_func("CRYPTO_lock") || $defs.push("-DHAVE_OPENSSL_110_THREADING_API")
have_struct_member("SSL", "ctx", "openssl/ssl.h") || $defs.push("-DHAVE_OPAQUE_OPENSSL")
have_func("BN_GENCB_new")
have_func("BN_GENCB_free")
have_func("BN_GENCB_get_arg")
have_func("EVP_MD_CTX_new")
have_func("EVP_MD_CTX_free")
have_func("HMAC_CTX_new")
have_func("HMAC_CTX_free")
OpenSSL.check_func("RAND_pseudo_bytes", "openssl/rand.h") # deprecated
have_func("X509_STORE_get_ex_data")
have_func("X509_STORE_set_ex_data")
have_func("X509_CRL_get0_signature")
have_func("X509_REQ_get0_signature")
have_func("X509_REVOKED_get0_serialNumber")
have_func("X509_REVOKED_get0_revocationDate")
have_func("X509_get0_tbs_sigalg")
have_func("X509_STORE_CTX_get0_untrusted")
have_func("X509_STORE_CTX_get0_cert")
have_func("X509_STORE_CTX_get0_chain")
have_func("OCSP_SINGLERESP_get0_id")
have_func("SSL_CTX_get_ciphers")
have_func("X509_up_ref")
have_func("X509_CRL_up_ref")
have_func("X509_STORE_up_ref")
have_func("SSL_SESSION_up_ref")
have_func("EVP_PKEY_up_ref")
OpenSSL.check_func_or_macro("SSL_CTX_set_tmp_ecdh_callback", "openssl/ssl.h") # removed
OpenSSL.check_func_or_macro("SSL_CTX_set_min_proto_version", "openssl/ssl.h")
have_func("SSL_CTX_get_security_level")
have_func("X509_get0_notBefore")
have_func("SSL_SESSION_get_protocol_version")

Logging::message "=== Checking done. ===\n"

create_header
create_makefile("openssl")
Logging::message "Done.\n"
