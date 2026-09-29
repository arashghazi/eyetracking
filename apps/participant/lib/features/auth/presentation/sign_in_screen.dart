import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/auth_controller.dart';
import 'auth_layout.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.auth,
    required this.onHaveInvitation,
  });

  final AuthController auth;
  final VoidCallback onHaveInvitation;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.auth.busy || !_formKey.currentState!.validate()) return;
    await widget.auth.signIn(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        final auth = widget.auth;
        return AuthLayout(
          title: 'Sign in',
          subtitle: 'Use the email address and password you registered with.',
          children: [
            if (auth.error != null) ...[
              MessageBanner(message: auth.error!, onDismiss: auth.dismissError),
              const SizedBox(height: 12),
            ],
            Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('email'),
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter your email address.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('password'),
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your password.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('sign-in-submit'),
                      onPressed: auth.busy ? null : _submit,
                      child: Text(auth.busy ? 'Signing in...' : 'Sign in'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('have-invitation'),
              onPressed: () {
                auth.dismissError();
                widget.onHaveInvitation();
              },
              child: const Text('I have an invitation'),
            ),
          ],
        );
      },
    );
  }
}
