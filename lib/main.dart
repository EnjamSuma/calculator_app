import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const CalculatorApp());

class CalcException implements Exception {
  final String message;
  const CalcException(this.message);
}

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const CalculatorPage(),
    );
  }
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

enum BtnKind { digit, operator, action, equals }

class _CalculatorPageState extends State<CalculatorPage> {
  static const int _maxDigits = 15;
  static const double _maxValue = 1e15;

  // ---- State (everything on screen is derived from these) ----
  String _input = ''; // number currently being typed
  double? _total; // running total (sequential evaluation)
  String? _op; // pending operator
  String _expr = ''; // expression shown above the main display
  String? _error; // fatal error (needs recovery)
  String? _notice; // non-fatal hint
  bool _justEvaluated = false;

  // ---- Derived values ----
  String get _display {
    if (_error != null) return _error!;
    if (_input.isNotEmpty) return _input;
    if (_total != null) return _fmt(_total!);
    return '0';
  }

  // ---- Logic ----
  void _reset() {
    _input = '';
    _total = null;
    _op = null;
    _expr = '';
    _error = null;
    _notice = null;
    _justEvaluated = false;
  }

  void _fail(String message, String attempted) {
    _error = message;
    _expr = attempted.trim();
    _input = '';
    _total = null;
    _op = null;
    _justEvaluated = false;
  }

  double _compute(double a, String op, double b) {
    double r;
    switch (op) {
      case '+':
        r = a + b;
        break;
      case '−':
        r = a - b;
        break;
      case '×':
        r = a * b;
        break;
      case '÷':
        if (b == 0) throw const CalcException('Cannot divide by zero');
        r = a / b;
        break;
      default:
        throw const CalcException('Unknown operator');
    }
    if (!r.isFinite || r.abs() > _maxValue) {
      throw const CalcException('Overflow: result too large');
    }
    return r;
  }

  String _fmt(double v) {
    if (v == 0) return '0';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    // Rounds away floating-point noise such as 0.1 + 0.2 = 0.30000000000000004
    return double.parse(v.toStringAsPrecision(12)).toString();
  }

  void _onDigit(String d) {
    setState(() {
      if (_error != null || _justEvaluated) _reset();
      _notice = null;
      final digits = _input.replaceAll('.', '').replaceAll('-', '').length;
      if (digits >= _maxDigits) {
        _notice = 'Maximum $_maxDigits digits';
        return;
      }
      _input = _input == '0' ? d : _input + d;
    });
  }

  void _onDecimal() {
    setState(() {
      if (_error != null || _justEvaluated) _reset();
      _notice = null;
      if (_input.contains('.')) {
        _notice = 'Only one decimal point per number';
        return;
      }
      _input = _input.isEmpty ? '0.' : '$_input.';
    });
  }

  void _onOperator(String sym) {
    setState(() {
      if (_error != null) return;
      _notice = null;

      if (_input.isNotEmpty) {
        final value = double.parse(_input);
        try {
          if (_total == null || _op == null) {
            _total = value;
            _expr = '$_input $sym';
          } else {
            _total = _compute(_total!, _op!, value);
            _expr = '$_expr $_input $sym';
          }
        } on CalcException catch (e) {
          _fail(e.message, '$_expr $_input $sym');
          return;
        }
        _input = '';
        _op = sym;
        _justEvaluated = false;
        return;
      }

      if (_total == null) {
        _notice = 'Enter a number first';
        return;
      }
      if (_op == null) {
        // Continue from a previous result
        _expr = '${_fmt(_total!)} $sym';
        _op = sym;
        _justEvaluated = false;
        return;
      }
      // Repeated operator: replace the pending one
      _op = sym;
      _expr = '${_expr.substring(0, _expr.length - 1)}$sym';
    });
  }

  void _onEquals() {
    setState(() {
      if (_error != null || _op == null) return;
      _notice = null;
      if (_input.isEmpty) {
        _notice = 'Enter a second number to finish';
        return;
      }
      try {
        final result = _compute(_total!, _op!, double.parse(_input));
        _expr = '$_expr $_input =';
        _total = result;
        _op = null;
        _input = '';
        _justEvaluated = true;
      } on CalcException catch (e) {
        _fail(e.message, '$_expr $_input =');
      }
    });
  }

  void _onBackspace() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_error != null || _justEvaluated) {
        _reset();
        return;
      }
      _notice = null;
      if (_input.isNotEmpty) {
        _input = _input.substring(0, _input.length - 1);
        if (_input == '-') _input = '';
        return;
      }
      if (_op != null && _total != null) {
        // Remove the operator and edit the running total again
        _input = _fmt(_total!);
        _total = null;
        _op = null;
        _expr = '';
      }
    });
  }

  void _onClearAll() {
    setState(_reset);
  }

  void _onLongPressClear() {
    HapticFeedback.heavyImpact();
    setState(() {
      _reset();
      _notice = 'Cleared';
    });
  }

  // ---- UI ----
  Widget _btn(
    String label,
    VoidCallback onTap, {
    int flex = 1,
    String? semantic,
    BtnKind kind = BtnKind.digit,
    VoidCallback? onLongPress,
  }) {
    final cs = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    switch (kind) {
      case BtnKind.operator:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case BtnKind.action:
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        break;
      case BtnKind.equals:
        bg = cs.primary;
        fg = cs.onPrimary;
        break;
      case BtnKind.digit:
        bg = cs.surfaceContainerHigh;
        fg = cs.onSurface;
        break;
    }
    final selected = kind == BtnKind.operator && _op == label;

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Semantics(
          button: true,
          label: semantic ?? label,
          selected: selected,
          onTap: onTap,
          onLongPress: onLongPress,
          excludeSemantics: true,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: selected
                  ? BorderSide(color: cs.onSecondaryContainer, width: 3)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 28, color: fg),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) =>
      Expanded(child: Row(children: children));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasError = _error != null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.bottomRight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_op != null && _total != null)
                        Text(
                          'Running total: ${_fmt(_total!)}',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _expr,
                          style: TextStyle(
                            fontSize: 22,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Semantics(
                        liveRegion: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _display,
                            style: TextStyle(
                              fontSize: hasError ? 36 : 64,
                              fontWeight: FontWeight.w300,
                              color: hasError ? cs.error : cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 24,
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            hasError
                                ? 'Press AC or a number to continue'
                                : (_notice ?? ''),
                            style: TextStyle(color: cs.tertiary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    _row([
                      _btn('AC', _onClearAll,
                          flex: 2,
                          semantic: 'All clear',
                          kind: BtnKind.action),
                      _btn('⌫', _onBackspace,
                          semantic: 'Backspace. Long press to clear all',
                          kind: BtnKind.action,
                          onLongPress: _onLongPressClear),
                      _btn('÷', () => _onOperator('÷'),
                          semantic: 'Divide', kind: BtnKind.operator),
                    ]),
                    _row([
                      _btn('7', () => _onDigit('7')),
                      _btn('8', () => _onDigit('8')),
                      _btn('9', () => _onDigit('9')),
                      _btn('×', () => _onOperator('×'),
                          semantic: 'Multiply', kind: BtnKind.operator),
                    ]),
                    _row([
                      _btn('4', () => _onDigit('4')),
                      _btn('5', () => _onDigit('5')),
                      _btn('6', () => _onDigit('6')),
                      _btn('−', () => _onOperator('−'),
                          semantic: 'Subtract', kind: BtnKind.operator),
                    ]),
                    _row([
                      _btn('1', () => _onDigit('1')),
                      _btn('2', () => _onDigit('2')),
                      _btn('3', () => _onDigit('3')),
                      _btn('+', () => _onOperator('+'),
                          semantic: 'Add', kind: BtnKind.operator),
                    ]),
                    _row([
                      _btn('0', () => _onDigit('0'), flex: 2),
                      _btn('.', _onDecimal, semantic: 'Decimal point'),
                      _btn('=', _onEquals,
                          semantic: 'Equals', kind: BtnKind.equals),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}