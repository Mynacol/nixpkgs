{ lib
, buildPythonPackage
, fetchFromGitHub

, flask
, limits
, ordered-set
, rich
, typing-extensions

, asgiref
, hiro
, pymemcache
, pytest-mock
, pytestCheckHook
, redis
, pymongo
}:

buildPythonPackage rec {
  pname = "Flask-Limiter";
  version = "3.1.0";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "alisaifee";
    repo = "flask-limiter";
    rev = "refs/tags/${version}";
    hash = "sha256-eAJRqyAH1j1NHYfagRZM2fPE6hm9+tJHD8FMqvgvMBI=";
  };

  postPatch = ''
    substituteInPlace requirements/main.txt \
      --replace "rich>=12,<13" "rich"

    sed -i "/--cov/d" pytest.ini

    # flask-restful is unmaintained and breaks regularly, don't depend on it
    sed -i "/import flask_restful/d" tests/test_views.py
  '';

  propagatedBuildInputs = [
    flask
    limits
    ordered-set
    rich
    typing-extensions
  ];

  checkInputs = [
    asgiref
    pytest-mock
    pytestCheckHook
    hiro
    redis
    pymemcache
    pymongo
  ];

  disabledTests = [
    # flask-restful is unmaintained and breaks regularly
    "test_flask_restful_resource"

    # Requires running a docker instance
    "test_clear_limits"
    "test_constructor_arguments_over_config"
    "test_custom_key_prefix"
    "test_custom_key_prefix_with_headers"
    "test_fallback_to_memory_backoff_check"
    "test_fallback_to_memory_config"
    "test_fallback_to_memory_with_global_override"
    "test_redis_request_slower_than_fixed_window"
    "test_redis_request_slower_than_moving_window"
    "test_reset_unsupported"

    # Requires redis
    "test_fallback_to_memory"
  ];

  disabledTestPaths = [
    # requires running redis/memcached/mongodb
    "tests/test_storage.py"
  ];

  pythonImportsCheck = [ "flask_limiter" ];

  meta = with lib; {
    description = "Rate limiting for flask applications";
    homepage = "https://flask-limiter.readthedocs.org/";
    license = licenses.mit;
  };
}
