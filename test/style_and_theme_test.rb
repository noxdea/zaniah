# frozen_string_literal: true

require_relative "test_helper"

class StyleAndThemeTest < Minitest::Test
  def test_style_inheritance_and_state_order
    parent = Zaniah::Layout::Style.new(text_color: "#fff", font_size: 18)
    child = Zaniah::Layout::Style.new(font_size: 12).inherit(parent)
    assert_equal "#fff", child[:text_color]
    assert_equal 12, child[:font_size]
    assert child.to_h.frozen?

    styles = Zaniah::StyleSet.new(Zaniah::Layout::Style.new(opacity: 1))
      .on(:hover, opacity: 0.8).on(:active, opacity: 0.6).on(:disabled, opacity: 0.4)
    assert_equal 0.4, styles.resolve(Set[:hover, :active, :disabled])[:opacity]
  end

  def test_transform_inverse_and_color_contrast
    transform = Zaniah::Transform.translate(10, 5).then(Zaniah::Transform.rotate(90)).then(Zaniah::Transform.scale(2))
    point = Zaniah::Point.new(3, 7)
    restored = transform.inverse.apply(transform.apply(point))
    assert_in_delta point.x, restored.x, 0.000001
    assert_in_delta point.y, restored.y, 0.000001
    assert_in_delta 21, Zaniah::Color.parse("#000").contrast_ratio("#fff"), 0.001
    assert_equal 0.25, Zaniah::Color.parse("#fff").with_alpha(0.25).a
  end

  def test_gradient_validation
    gradient = Zaniah::Gradient.linear(stops: [[0, "#000"], [1, "#fff"]])
    assert_equal :linear, gradient.kind
    assert gradient.stops.frozen?
    assert_raises(ArgumentError) { Zaniah::Gradient.linear(stops: [[1, "#000"], [0, "#fff"]]) }
  end

  def test_themes_have_readable_primary_text
    [Zaniah::Theme.dark, Zaniah::Theme.light, Zaniah::Theme.high_contrast].each do |theme|
      assert_operator theme.colors.text.contrast_ratio(theme.colors.background), :>=, 4.5
      assert_operator theme.colors.accent_text.contrast_ratio(theme.colors.accent), :>=, 4.5
    end
    assert Zaniah::Theme.dark.motion.duration_base.positive?
    refute Zaniah::Theme.dark.motion.reduced?
  end

  def test_hover_resolves_on_first_rendered_frame
    window = Zaniah::Platform.open_window(width: 40, height: 40)
    element = Zaniah::Div.new.w(20).h(20).bg("#f00").hover { |style| style.bg("#0f0") }
    window.input(Zaniah::Input::MouseMove.new(Zaniah::Point.new(10, 10), []))
    window.render(element)
    assert_equal [0, 255, 0, 255], window.device.pixels.byteslice((10 * 40 + 10) * 4, 4).bytes
  ensure
    window&.close
  end

  def test_active_overrides_hover_and_hover_reaches_ancestors
    window = Zaniah::Platform.open_window(width: 40, height: 40)
    child = Zaniah::Div.new.w(20).h(20).active { |style| style.bg("#00f") }
    parent = Zaniah::Div.new.w(30).h(30).bg("#f00").hover { |style| style.bg("#0f0") }.child(child)
    point = Zaniah::Point.new(10, 10)
    window.input(Zaniah::Input::MouseMove.new(point, []))
    window.input(Zaniah::Input::MouseDown.new(point, :left, [], 1))
    window.render(parent)
    assert_equal [0, 0, 255, 255], window.device.pixels.byteslice((10 * 40 + 10) * 4, 4).bytes
    assert parent.resolved_style[:background]
  ensure
    window&.close
  end

  def test_app_provides_theme_to_frame_context
    app = Zaniah::App.new
    window = app.open_window
    assert_same Zaniah::Theme.dark, Zaniah::FrameContext.new(window).theme
    app.global(:theme, Zaniah::Theme.light)
    assert_same Zaniah::Theme.light, Zaniah::FrameContext.new(window).theme
  ensure
    window&.close
    app&.executor&.shutdown
  end
end
