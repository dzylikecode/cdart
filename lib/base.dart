// ignore_for_file: camel_case_types

typedef float = double;

class Ref<T> {
  final List<T> _ref;
  Ref(T value) : _ref = [value];
  T get value => _ref[0];
  set value(T newValue) => _ref[0] = newValue;
}

extension FloatExt on double {
  float get f => this;
}
