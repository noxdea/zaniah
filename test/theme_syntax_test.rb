# frozen_string_literal: true

require_relative "test_helper"

class ThemeSyntaxTest < Minitest::Test
  def test_defaults_and_custom_syntax_survive_theme_updates
    theme = Zaniah::Theme.dark
    assert_equal theme.colors.accent, theme.syntax.color("keyword.control")
    assert_equal theme.colors.text, theme.syntax.color(:unknown)

    custom = theme.syntax.with(keyword: theme.colors.danger)
    updated = Zaniah::Theme.new(**theme.to_h.merge(syntax: custom))
    assert_equal theme.colors.danger, updated.syntax.color(:keyword)
    assert_same custom, updated.with(motion: theme.motion.with(reduced: true)).syntax
    assert updated.frozen?
    assert_raises(ArgumentError) { Zaniah::Theme.new(**theme.to_h.merge(syntax: false)) }
  end
end
