import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../state/auth_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';
import 'login_screen.dart'
    show BrandMark, FieldLabel, InputField, OrDivider, SocialButton, Validators;

/// Account creation screen — mirrors the login layout with name + terms.
/// On success the auth gate takes over; when the project has email
/// confirmation enabled we tell the user to check their inbox instead.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, this.onCreate, this.onSignIn});
  final VoidCallback? onCreate;
  final VoidCallback? onSignIn;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _agreed = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthStore>();
    if (auth.busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!_agreed) {
      _toast('Please accept the Terms to continue.');
      return;
    }
    FocusScope.of(context).unfocus();

    final ok = await auth.signUp(
      fullName: _name.text,
      email: _email.text,
      password: _password.text,
    );
    if (!mounted) return;

    if (!ok) {
      _toast(auth.error ?? 'Could not create the account.');
      return;
    }
    if (auth.awaitingEmailConfirmation) {
      _toast('Almost there — confirm your email, then sign in.');
      widget.onSignIn?.call();
    } else {
      widget.onCreate?.call();
    }
  }

  Future<void> _google() async {
    final auth = context.read<AuthStore>();
    if (auth.busy) return;
    final ok = await auth.signInWithGoogle();
    if (!mounted || ok) return;
    _toast(auth.error ?? 'Google sign-in failed.');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: context.p.ink,
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
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  children: [
                    const SizedBox(height: 8),
                    const BrandMark(),
                    const SizedBox(height: 26),
                    Text('Create your account',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7)),
                    const SizedBox(height: 6),
                    Text('Start turning your syllabus into a plan.',
                        style: TextStyle(color: p.ink2, fontSize: 14.5)),
                    const SizedBox(height: 24),

                    const FieldLabel('Full name'),
                    InputField(
                      hint: 'Enter your full name',
                      icon: Symbols.person,
                      controller: _name,
                      validator: (v) => Validators.required(v, 'Full name'),
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      enabled: !busy,
                    ),
                    const SizedBox(height: 16),
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
                      hint: 'At least 8 characters',
                      icon: Symbols.lock,
                      obscure: true,
                      controller: _password,
                      validator: Validators.signupPassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      enabled: !busy,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 18),

                    _TermsRow(
                      agreed: _agreed,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => _agreed = v),
                    ),
                    const SizedBox(height: 22),
                    PillButton(busy ? 'Creating…' : 'Create account',
                        trailingIcon: Symbols.arrow_forward,
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
                onTap: widget.onSignIn,
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: 'Already have an account?  ',
                      style: TextStyle(color: p.ink2, fontSize: 14)),
                  TextSpan(
                      text: 'Sign in',
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

/// Tappable terms checkbox, keeping the design's custom check tile.
class _TermsRow extends StatelessWidget {
  const _TermsRow({required this.agreed, this.onChanged});
  final bool agreed;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!agreed),
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: agreed ? p.primary : p.card,
              borderRadius: BorderRadius.circular(7),
              border: agreed ? null : Border.all(color: p.line2, width: 1.4),
              boxShadow: agreed ? p.glow : null,
            ),
            child: agreed
                ? Icon(Symbols.check,
                    color: p.onPrimary, size: 16, weight: 700)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(
                style:
                    TextStyle(color: p.ink2, fontSize: 12.5, height: 1.45),
                children: [
                  const TextSpan(text: 'I agree to the '),
                  TextSpan(
                      text: 'Terms',
                      style: TextStyle(
                          color: p.primary, fontWeight: FontWeight.w800)),
                  const TextSpan(text: ' and '),
                  TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                          color: p.primary, fontWeight: FontWeight.w800)),
                  const TextSpan(text: '.'),
                ])),
          ),
        ],
      ),
    );
  }
}
