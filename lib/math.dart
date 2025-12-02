import 'dart:math' as math;

const NAN = double.nan;
const INFINITY = double.infinity;

const HUGE_VALF = double.infinity;
const HUGE_VAL = double.infinity;
const HUGE_VALL = double.infinity;

bool isless<T extends num>(T x, T y) => x < y;
bool islessequal<T extends num>(T x, T y) => x <= y;
bool islessgreater<T extends num>(T x, T y) => x < y || x > y;
bool isgreater<T extends num>(T x, T y) => x > y;
bool isgreaterequal<T extends num>(T x, T y) => x >= y;

const acos = math.acos;
const acosf = math.acos;
const acosl = math.acos;

const M_E = math.e;
