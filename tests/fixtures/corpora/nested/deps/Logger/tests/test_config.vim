vim9script

##############################################################################
# Plugin_Name: Logger
# Tests config.vim: the plugin key, the lookup order of plugin, global,
# and default values, and the fallback for a value of the wrong type.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/config.vim' as C
import './fixtures.vim' as F

def Test_key_is_lowercase_and_safe(): void
  F.Reset()
  assert_equal('foo', C.Config.new('Foo').key)
  assert_equal('my_plugin_2', C.Config.new('My-Plugin 2').key)
enddef

def Test_plugin_value_overrides_global_and_default(): void
  F.Reset()
  var config = C.Config.new('Foo')
  assert_equal(10, config.GetNumber('log_retention', 10))
  g:logger_log_retention = 5
  assert_equal(5, config.GetNumber('log_retention', 10))
  g:logger_foo_log_retention = 3
  assert_true(config.HasOwn('log_retention'))
  assert_equal(3, config.GetNumber('log_retention', 10))
  assert_equal(5, C.Config.new('Bar').GetNumber('log_retention', 10))
  F.Reset()
enddef

def Test_global_only_skips_plugin_value(): void
  F.Reset()
  g:logger_log_dir = '/global'
  g:logger_foo_log_dir = '/plugin'
  var config = C.Config.new('Foo')
  assert_equal('/plugin', config.GetString('log_dir', '/default'))
  assert_equal('/global', config.GetString('log_dir', '/default', false))
  F.Reset()
enddef

def Test_wrong_type_returns_default(): void
  F.Reset()
  var config = C.Config.new('Foo')
  g:logger_foo_level = 'high'
  assert_equal(2, config.GetNumber('level', 2))
  g:logger_foo_level = true
  assert_equal(1, config.GetNumber('level', 2))
  g:logger_foo_echo = 'yes'
  assert_true(config.GetBool('echo', true))
  g:logger_foo_echo = 0
  assert_false(config.GetBool('echo', true))
  g:logger_foo_log_dir = 42
  assert_equal('/default', config.GetString('log_dir', '/default'))
  F.Reset()
enddef

export def RunAll(): void
  Test_key_is_lowercase_and_safe()
  Test_plugin_value_overrides_global_and_default()
  Test_global_only_skips_plugin_value()
  Test_wrong_type_returns_default()
enddef
