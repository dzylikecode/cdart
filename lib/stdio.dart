import 'dart:io';

import 'src/stdio_impl.dart';

final printf = stdout.write;

bool ferror(FILE? file) => false;
