# frozen_string_literal: true

module Zaniah
  Transform = Data.define(:a, :b, :c, :d, :tx, :ty) do
    def self.identity = new(1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    def self.translate(x, y = 0) = new(1.0, 0.0, 0.0, 1.0, x.to_f, y.to_f)
    def self.scale(x, y = x) = new(x.to_f, 0.0, 0.0, y.to_f, 0.0, 0.0)

    def self.rotate(degrees)
      radians = degrees * Math::PI / 180
      cosine, sine = Math.cos(radians), Math.sin(radians)
      new(cosine, sine, -sine, cosine, 0.0, 0.0)
    end

    def self.skew(x: 0, y: 0)
      new(1.0, Math.tan(y * Math::PI / 180), Math.tan(x * Math::PI / 180), 1.0, 0.0, 0.0)
    end

    def compose(other)
      Transform.new(a * other.a + c * other.b, b * other.a + d * other.b,
        a * other.c + c * other.d, b * other.c + d * other.d,
        a * other.tx + c * other.ty + tx, b * other.tx + d * other.ty + ty)
    end

    def then(other) = other.compose(self)
    def translate(x, y = 0) = self.then(Transform.translate(x, y))
    def scale(x, y = x) = self.then(Transform.scale(x, y))
    def rotate(degrees) = self.then(Transform.rotate(degrees))
    def skew(x: 0, y: 0) = self.then(Transform.skew(x: x, y: y))
    def apply(point) = Point.new(a * point.x + c * point.y + tx, b * point.x + d * point.y + ty)

    def inverse
      determinant = a * d - b * c
      raise ArgumentError, "transform is not invertible" if determinant.abs < Float::EPSILON
      Transform.new(d / determinant, -b / determinant, -c / determinant, a / determinant,
        (c * ty - d * tx) / determinant, (b * tx - a * ty) / determinant)
    end
  end
end
