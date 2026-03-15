// dart format off
import '../base.dart';
import '../stdarg.dart';
import '../limits.dart';
import '../stddef.dart';
import '../ctype.dart';
import '../stdio.dart';

import 'stdio_impl.dart';


sealed class Arg {
  const Arg();
}

final class ArgInt extends Arg {
  final int i;
  const ArgInt(this.i);
}

final class ArgPtr extends Arg {
  final chars p;
  const ArgPtr(this.p);
}

final class ArgDouble extends Arg {
  final double f;
  const ArgDouble(this.f);
}


const ALT_FORM = '#';
const ZERO_PAD = '0';
const LEFT_ADJ = '-';
const PAD_POS = ' ';
const MARK_POS = '+';
const GROUPED = '\'';

const FLAGMASK = {ALT_FORM, ZERO_PAD, LEFT_ADJ, PAD_POS, MARK_POS, GROUPED};

enum ArgType {
	BARE, LPRE, LLPRE, HPRE, HHPRE, BIGLPRE,
	ZTPRE, JPRE,
	STOP,
	PTR, INT, UINT, ULLONG,
	LONG, ULONG,
	SHORT, USHORT, CHAR, UCHAR,
	LLONG, SIZET, IMAX, UMAX, PDIFF, UIPTR,
	DBL, LDBL,
	NOARG,
	MAXSTATE;

  bool get toBool => this != ArgType.BARE;

  bool operator <(ArgType other) => index < other.index;
  bool operator <=(ArgType other) => index <= other.index;
}

String S(String x) => x;
bool OOB(String x) => (x)-'A' > 'z'-'A';


final states = <ArgType, Map<String, ArgType>>{
  .BARE: { /* 0: bare types */
    S('d'): .INT, S('i'): .INT,
    S('o'): .UINT, S('u'): .UINT, S('x'): .UINT, S('X'): .UINT,
    S('e'): .DBL, S('f'): .DBL, S('g'): .DBL, S('a'): .DBL,
    S('E'): .DBL, S('F'): .DBL, S('G'): .DBL, S('A'): .DBL,
    S('c'): .INT, S('C'): .UINT,
    S('s'): .PTR, S('S'): .PTR, S('p'): .UIPTR, S('n'): .PTR,
    S('m'): .NOARG,
    S('l'): .LPRE, S('h'): .HPRE, S('L'): .BIGLPRE,
    S('z'): .ZTPRE, S('j'): .JPRE, S('t'): .ZTPRE,
  }, .LPRE: { /* 1: l-prefixed */
    S('d'): .LONG, S('i'): .LONG,
    S('o'): .ULONG, S('u'): .ULONG, S('x'): .ULONG, S('X'): .ULONG,
    S('e'): .DBL, S('f'): .DBL, S('g'): .DBL, S('a'): .DBL,
    S('E'): .DBL, S('F'): .DBL, S('G'): .DBL, S('A'): .DBL,
    S('c'): .UINT, S('s'): .PTR, S('n'): .PTR,
    S('l'): .LLPRE,
  }, .LLPRE: { /* 2: ll-prefixed */
    S('d'): .LLONG, S('i'): .LLONG,
    S('o'): .ULLONG, S('u'): .ULLONG,
    S('x'): .ULLONG, S('X'): .ULLONG,
    S('n'): .PTR,
  }, .HPRE: { /* 3: h-prefixed */
    S('d'): .SHORT, S('i'): .SHORT,
    S('o'): .USHORT, S('u'): .USHORT,
    S('x'): .USHORT, S('X'): .USHORT,
    S('n'): .PTR,
    S('h'): .HHPRE,
  }, .HHPRE: { /* 4: hh-prefixed */
    S('d'): .CHAR, S('i'): .CHAR,
    S('o'): .UCHAR, S('u'): .UCHAR,
    S('x'): .UCHAR, S('X'): .UCHAR,
    S('n'): .PTR,
  }, .BIGLPRE: { /* 5: L-prefixed */
    S('e'): .LDBL, S('f'): .LDBL, S('g'): .LDBL, S('a'): .LDBL,
    S('E'): .LDBL, S('F'): .LDBL, S('G'): .LDBL, S('A'): .LDBL,
    S('n'): .PTR,
  }, .ZTPRE: { /* 6: z- or t-prefixed (assumed to be same size) */
    S('d'): .PDIFF, S('i'): .PDIFF,
    S('o'): .SIZET, S('u'): .SIZET,
    S('x'): .SIZET, S('X'): .SIZET,
    S('n'): .PTR,
  }, .JPRE: { /* 7: j-prefixed */
    S('d'): .IMAX, S('i'): .IMAX,
    S('o'): .UMAX, S('u'): .UMAX,
    S('x'): .UMAX, S('X'): .UMAX,
    S('n'): .PTR,
  }
};


int vfprintf(FILE f, chars fmt, va_list ap) {
  va_list ap2 = .new([]);
  List<ArgType> nl_type = .filled(NL_ARGMAX + 1, .BARE);
  List<Arg> nl_arg = List.filled(NL_ARGMAX + 1, const ArgInt(0));
  chars internal_buf = '', saved_buf = '';
  int olderr = 0;
  int ret = 0;

  va_copy(ap2, ap);

  if (printf_core(null, fmt, ap2, nl_arg, nl_type) < 0) {
    return -1;
  }
}

int get overflow => -1;
int get inval => -1;

int printf_core(FILE? f, chars fmt, va_list ap, List<Arg> nl_arg, List<ArgType> nl_type) {
  chars_view a, z, s = chars_view(fmt);
  unsigned l10n = 0;
  Set<String> fl = {};
  int w = 0, p; bool xp = false;
  Arg arg;
  int argpos;
  ArgType st = .BARE, ps = .BARE;
  int cnt = 0, l = 0;
  size_t i;
  chars buf;
  chars prefix;
  int t, pl;
  wchar_t wc, ws;
  chars mb;
	for (;;) {
		/* This error is only specified for snprintf, but since it's
		 * unspecified for other forms, do the same. Stop immediately
		 * on overflow; otherwise %n could produce wrong results. */
		if (l > INT_MAX - cnt) return overflow;

		/* Update output count, end loop when fmt is exhausted */
		cnt += l;
		if (s.current == '') break;

		/* Handle literal text and %% format specifiers */
    // 找到 %
		for (a=s; s.current.isNotEmpty && s.current != '%'; s++);
    // %% 会当作 %
		for (z=s; s[0]=='%' && s[1]=='%'; z++, s+=2);
		if (z-a > INT_MAX-cnt) return overflow;
		l = z-a;
		if (f.toBool) out(f!, a, l);
		if (l.toBool) continue;

    // %2$ 表示位置参数
		if (isdigit(s[1]) && s[2]=='\$') {
			l10n=1;
			argpos = s[1]-'0';
			s+=3;
		} else {
			argpos = -1;
			s++;
		}

		/* Read modifier flags */
		for (fl={}; FLAGMASK.contains(s.current); s++)
			fl.add(s.current);

		/* Read field width */
		if (s.current=='*') {
			if (isdigit(s[1]) && s[2]=='\$') {
				l10n=1;
				if (!f.toBool) {nl_type[s[1]-'0'] = .INT; w = 0;}
				else w = (nl_arg[s[1]-'0'] as ArgInt).i;
				s+=3;
			} else if (!l10n.toBool) {
				w = f.toBool ? va_arg(ap.current, int) : 0;
				s++;
			} else return inval;
			if (w<0) {fl.add(LEFT_ADJ); w=-w;}
		} else if (((w, s)=getint(s))case final ret when ret.$1 < 0) return overflow;

		/* Read precision */
		if (s.current=='.' && s[1]=='*') {
			if (isdigit(s[2]) && s[3]=='\$') {
				if (!f.toBool) {nl_type[s[2]-'0'] = .INT; p = 0;}
				else p = (nl_arg[s[2]-'0'] as ArgInt).i;
				s+=4;
			} else if (!l10n.toBool) {
				p = f.toBool ? va_arg(ap, int) : 0;
				s+=2;
			} else return inval;
			xp = (p>=0);
		} else if (s.current=='.') {
			s++;
			(p, s) = getint(s);
			xp = true;
		} else {
			p = -1;
			xp = false;
		}

		/* Format specifier state machine */
		st=.BARE;
		do {
			if (OOB(s.current)) return inval;
			ps=st;
			st=states[st]![s.current] ?? .BARE;
      s++;
		} while (st < .STOP); // states 表里面没有 STOP, <= STOP 所以与之等价
		if (!st.toBool) return inval;

		/* Check validity of argument type (nl/normal) */
		if (st==.NOARG) {
			if (argpos>=0) return inval;
		} else {
			if (argpos>=0) {
				if (!f.toBool) nl_type[argpos]=st;
				else arg=nl_arg[argpos];
			} else if (f.toBool) pop_arg(arg, st, ap);
			else return 0;
		}

		if (!f.toBool) continue;

		/* Do not process any new directives once in error state. */
		if (ferror(f)) return -1;

		z = buf + sizeof(buf);
		prefix = "-+   0X0x";
		pl = 0;
		t = s[-1];

		/* Transform ls,lc -> S,C */
		if (ps.toBool && (t&15)==3) t&=~32;

		/* - and 0 flags are mutually exclusive */
		if (fl.contains(LEFT_ADJ)) fl.remove(ZERO_PAD);

		switch(t) {
		case 'n':
			switch(ps) {
			case .BARE: *(int *)arg.p = cnt; break;
			case .LPRE: *(long *)arg.p = cnt; break;
			case .LLPRE: *(long long *)arg.p = cnt; break;
			case .HPRE: *(unsigned short *)arg.p = cnt; break;
			case .HHPRE: *(unsigned char *)arg.p = cnt; break;
			case .ZTPRE: *(size_t *)arg.p = cnt; break;
			case .JPRE: *(uintmax_t *)arg.p = cnt; break;
			}
			continue;
		case 'p':
			p = MAX(p, 2*sizeof(void*));
			t = 'x';
			fl.add(ALT_FORM);
		case 'x': case 'X':
			a = fmt_x(arg.i, z, t&32);
			if (arg.i && (fl.contains(ALT_FORM))) prefix+=(t>>4), pl=2;
			goto ifmt_tail;
		case 'o':
			a = fmt_o(arg.i, z);
			if ((fl.contains(ALT_FORM)) && p<z-a+1) p=z-a+1;
			goto ifmt_tail;
		case 'd': case 'i':
			pl=1;
			if (arg.i>INTMAX_MAX) {
				arg.i=-arg.i;
			} else if (fl.contains(MARK_POS)) {
				prefix++;
			} else if (fl.contains(PAD_POS)) {
				prefix+=2;
			} else pl=0;
		case 'u':
			a = fmt_u(arg.i, z);
		ifmt_tail:
			if (xp && p<0) goto overflow;
			if (xp) fl.remove(ZERO_PAD);
			if (!arg.i && !p) {
				a=z;
				break;
			}
			p = MAX(p, z-a + !arg.i);
			break;
		narrow_c:
		case 'c':
			*(a=z-(p=1))=arg.i;
			fl.remove(ZERO_PAD);
			break;
		case 'm':
			if (1) a = strerror(errno); else
		case 's':
			a = arg.p ? arg.p : "(null)";
			z = a + strnlen(a, p<0 ? INT_MAX : p);
			if (p<0 && *z) goto overflow;
			p = z-a;
			fl.remove(ZERO_PAD);
			break;
		case 'C':
			if (!arg.i) goto narrow_c;
			wc[0] = arg.i;
			wc[1] = 0;
			arg.p = wc;
			p = -1;
		case 'S':
			ws = arg.p;
			for (i=l=0; i<p && *ws && (l=wctomb(mb, *ws++))>=0 && l<=p-i; i+=l);
			if (l<0) return -1;
			if (i > INT_MAX) goto overflow;
			p = i;
			pad(f, ' ', w, p, fl);
			ws = arg.p;
			for (i=0; i<0U+p && *ws && i+(l=wctomb(mb, *ws++))<=p; i+=l)
				out(f, mb, l);
			pad(f, ' ', w, p, fl^LEFT_ADJ);
			l = w>p ? w : p;
			continue;
		case 'e': case 'f': case 'g': case 'a':
		case 'E': case 'F': case 'G': case 'A':
			if (xp && p<0) return overflow;
			l = fmt_fp(f, arg.f, w, p, fl, t, ps);
			if (l<0) return overflow;
			continue;
		}

		if (p < z-a) p = z-a;
		if (p > INT_MAX-pl) return overflow;
		if (w < pl+p) w = pl+p;
		if (w > INT_MAX-cnt) return overflow;

		pad(f, ' ', w, pl+p, fl);
		out(f, prefix, pl);
		pad(f, '0', w, pl+p, fl^ZERO_PAD);
		pad(f, '0', p, z-a, 0);
		out(f, a, z-a);
		pad(f, ' ', w, pl+p, fl^LEFT_ADJ);

		l = w;
	}
  return overflow;
}

void out(FILE f,  chars_view s, size_t l)
{
	if (!ferror(f)) __fwritex((void *)s, l, f);
}

(int, chars_view) getint(chars_view s) {
	int i;
	for (i=0; isdigit(s.current); s++) {
		 i = 10*i + (s.current-'0');
	}
	return (i, s);
}