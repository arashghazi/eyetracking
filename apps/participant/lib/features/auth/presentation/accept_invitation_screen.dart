import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/auth_controller.dart';
import 'auth_layout.dart';

class AcceptInvitationScreen extends StatefulWidget {
  const AcceptInvitationScreen({
    super.key,
    required this.auth,
    required this.onBack,
    this.initialToken = '',
  });

  final AuthController auth;
  final VoidCallback onBack;
  final String initialToken;

  @override
  State<AcceptInvitationScreen> createState() => _AcceptInvitationScreenState();
}

class _AcceptInvitationScreenState extends State<AcceptInvitationScreen> {
  static const minPasswordLength = 8;

  final _formKey = GlobalKey<FormState>();
  late final _token = TextEditingController(text: widget.initialToken);
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _token.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.auth.busy || !_formKey.currentState!.validate()) return;
    await widget.auth.acceptInvitation(
      token: _token.text,
      email: _email.text,
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        final auth = widget.auth;
        return AuthLayout(
          title: 'Accept your invitation',
          subtitle: 'Enter the invitation code you were given and choose the '
              'email address and password you will sign in with.',
          children: [
            if (auth.notice != null) ...[
              MessageBanner(
                key: const Key('auth-notice'),
                message: auth.notice!,
                kind: BannerKind.success,
                onDismiss: auth.dismissNotice,
              ),
              const SizedBox(height: 12),
            ],
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
                      key: const Key('invitation-token'),
                      controller: _token,
                      decoration:
                          const InputDecoration(labelText: 'Invitation code'),
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the invitation code.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('email'),
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter a valid email address.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('password'),
                      controller: _password,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        helperText: 'At least $minPasswordLength characters.',
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => (v == null || v.length < minPasswordLength)
                          ? 'Use at least $minPasswordLength characters.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('accept-submit'),
                      onPressed: auth.busy ? null : _submit,
                      child: Text(
                        auth.busy ? 'Creating account...' : 'Accept and sign in',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('back-to-sign-in'),
              onPressed: () {
                auth.dismissError();
                widget.onBack();
              },
              child: const Text('Back to sign in'),
            ),
          ],
        );
      },
    );
  }
}
