import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/auth_controller.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth});

  final AuthController auth;

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
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListenableBuilder(
                listenable: widget.auth,
                builder: (context, _) {
                  final auth = widget.auth;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'EyeTracking practice',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                      const SizedBox(height: 4),
                      Text('Research Admin', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in with your staff account.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (auth.error != null) ...[
                                MessageBanner(
                                  message: auth.error!,
                                  onDismiss: auth.dismissError,
                                ),
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
                                        decoration: const InputDecoration(
                                          labelText: 'Email',
                                        ),
                                        keyboardType: TextInputType.emailAddress,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [AutofillHints.email],
                                        validator: (v) =>
                                            (v == null || !v.contains('@'))
                                                ? 'Enter your email address.'
                                                : null,
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        key: const Key('password'),
                                        controller: _password,
                                        decoration: const InputDecoration(
                                          labelText: 'Password',
                                        ),
                                        obscureText: true,
                                        textInputAction: TextInputAction.done,
                                        autofillHints: const [
                                          AutofillHints.password,
                                        ],
                                        onFieldSubmitted: (_) => _submit(),
                                        validator: (v) =>
                                            (v == null || v.isEmpty)
                                                ? 'Enter your password.'
                                                : null,
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton(
                                        key: const Key('sign-in-submit'),
                                        onPressed: auth.busy ? null : _submit,
                                        child: Text(
                                          auth.busy ? 'Signing in...' : 'Sign in',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
