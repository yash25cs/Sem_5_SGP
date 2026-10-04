import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../state/auth_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';

/// Sign-in screen with brand mark, email/password fields, and social options.
/// Sign-in runs through [AuthStore]; the auth gate in `main.dart` reacts to the
/// resulting session, so there's no manual navigation on success.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onSignIn, this.onSignUp});
  final VoidCallback? onSignIn;
  final VoidCallback? onSignUp;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthStore>();
    if (auth.busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final ok = await auth.signIn(_email.text, _password.text);
    if (!mounted) return;
    if (ok) {
      widget.onSignIn?.call();
    } else {
      _toast(auth.error ?? 'Could not sign in.');
    }
  }

  Future<void> _google() async {
    final auth = context.read<AuthStore>();
    if (auth.busy) return;
    final ok = await auth.signInWithGoogle();
    if (!mounted || ok) return;
    _toast(auth.error ?? 'Google sign-in failed.');
  }

  Future<void> _forgotPassword() async {
    final auth = context.read<AuthStore>();
    if (Validators.email(_email.text) != null) {
      _toast('Enter your email first, then tap Forgot password.');
      return;
    }
    final ok = await auth.sendPasswordReset(_email.text);
    if (!mounted) return;
    _toast(ok
        ? 'Reset link sent to ${_email.text.trim()}.'
        : (auth.error ?? 'Could not send the reset link.'));
  }

  void _toast(String message) {
    final p = context.p;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: p.ink,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final busy = context.watch<AuthStore>().busy;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Expanded(
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  children: [
                    const SizedBox(height: 12),
                    const BrandMark(),
                    const SizedBox(height: 30),
                    Text('Welcome back',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7)),
                    const SizedBox(height: 6),
                    Text('Sign in to pick up your roadmap.',
                        style: TextStyle(color: p.ink2, fontSize: 14.5)),
                    const SizedBox(height: 26),

                    const FieldLabel('Email'),
                    InputField(
                      hint: 'Enter your email',
                      icon: Symbols.mail,
                      controller: _email,
                      validator: Validators.email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      enabled: !busy,
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Password'),
                    InputField(
                      hint: 'Enter your password',
                      icon: Symbols.lock,
                      obscure: true,
                      controller: _password,
                      validator: Validators.password,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      enabled: !busy,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: busy ? null : _forgotPassword,
                        child: Text('Forgot password?',
                            style: TextStyle(
                                color: p.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 22),
                    PillButton(busy ? 'Signing in…' : 'Sign in',
                        onTap: busy ? null : _submit),
                    const SizedBox(height: 20),
                    const OrDivider(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                            child: SocialButton(
                                label: 'Google',
                                icon: Symbols.g_mobiledata,
                                onTap: busy ? null : _google)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: SocialButton(
                                label: 'Apple', icon: Symbols.phone_iphone)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 22, top: 6),
            child: Center(
              child: GestureDetector(
                onTap: widget.onSignUp,
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: 'New here?  ',
                      style: TextStyle(color: p.ink2, fontSize: 14)),
                  TextSpan(
                      text: 'Create an account',
                      style: TextStyle(
                          color: p.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ])),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The StudyTrail wordmark + logo tile used on auth screens.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.center = true});
  final bool center;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: p.glow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/images/studytrail_logo.jpg',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: 'Study',
              style: TextStyle(
                  color: p.primary2,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6)),
          TextSpan(
              text: 'Trail',
              style: TextStyle(
                  color: p.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6)),
        ])),
      ],
    );
    return center ? Center(child: row) : row;
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: TextStyle(
                color: context.p.ink2,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      );
}

/// Rounded text field with a leading icon. When [obscure] is set it manages
/// its own show/hide toggle, so callers don't pass a trailing icon for that.
class InputField extends StatefulWidget {
  const InputField({
    super.key,
    required this.hint,
    this.icon,
    this.trailing,
    this.obscure = false,
    this.controller,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.enabled = true,
    this.onSubmitted,
  });

  final String hint;
  final IconData? icon;
  final IconData? trailing;
  final bool obscure;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  State<InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<InputField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final hintStyle = TextStyle(color: p.ink3, fontSize: 14.5);

    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );

    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      enabled: widget.enabled,
      obscureText: _hidden,
      onFieldSubmitted: widget.onSubmitted,
      style: TextStyle(color: p.ink, fontSize: 14.5),
      cursorColor: p.primary,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: hintStyle,
        filled: true,
        fillColor: p.card,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        prefixIcon: widget.icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 16, right: 12),
                child: Icon(widget.icon, color: p.ink3, size: 20),
              ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: widget.obscure
            ? IconButton(
                onPressed: () => setState(() => _hidden = !_hidden),
                icon: Icon(
                  _hidden ? Symbols.visibility_off : Symbols.visibility,
                  color: p.ink3,
                  size: 21,
                ),
                tooltip: _hidden ? 'Show password' : 'Hide password',
              )
            : (widget.trailing == null
                ? null
                : Icon(widget.trailing, color: p.ink3, size: 21)),
        enabledBorder: border(p.line, 1.2),
        disabledBorder: border(p.line, 1.2),
        focusedBorder: border(p.primary, 1.6),
        errorBorder: border(p.error, 1.2),
        focusedErrorBorder: border(p.error, 1.6),
        errorStyle: TextStyle(color: p.error, fontSize: 12),
      ),
    );
  }
}

/// Shared field validators for the auth forms.
class Validators {
  const Validators._();

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Email is required.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? password(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Password is required.';
    // Matches the Supabase Auth default minimum.
    if (s.length < 6) return 'Use at least 6 characters.';
    return null;
  }

  static String? signupPassword(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Password is required.';
    if (s.length < 8) return 'Use at least 8 characters.';
    return null;
  }

  static String? required(String? v, String label) {
    if ((v ?? '').trim().isEmpty) return '$label is required.';
    return null;
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      children: [
        Expanded(child: Divider(color: p.line, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or continue with',
              style: TextStyle(color: p.ink3, fontSize: 12.5)),
        ),
        Expanded(child: Divider(color: p.line, thickness: 1)),
      ],
    );
  }
}

class SocialButton extends StatelessWidget {
  const SocialButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line2, width: 1.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: p.ink, size: 22),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
