import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/client_repository.dart';
import '../models/client_profile.dart';
import '../models/questionnaire_answers.dart';
import 'auth_provider.dart';

/// Dépôt client adossé au backend, avec le token de la session courante.
/// Se reconstruit automatiquement à la connexion / déconnexion.
final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  final token = ref.watch(authProvider).session?.token;
  return ApiClientRepository(token: token);
});

class SessionFlowState {
  final ClientProfile? client;
  final QuestionnaireAnswers? answers;

  const SessionFlowState({this.client, this.answers});

  SessionFlowState copyWith({
    ClientProfile? client,
    QuestionnaireAnswers? answers,
  }) {
    return SessionFlowState(
      client: client ?? this.client,
      answers: answers ?? this.answers,
    );
  }
}

class SessionFlowNotifier extends Notifier<SessionFlowState> {
  @override
  SessionFlowState build() => const SessionFlowState();

  void setClient(ClientProfile client) {
    state = state.copyWith(client: client);
  }

  void setAnswers(QuestionnaireAnswers answers) {
    state = state.copyWith(answers: answers);
  }

  void reset() {
    state = const SessionFlowState();
  }
}

final sessionFlowProvider =
    NotifierProvider<SessionFlowNotifier, SessionFlowState>(
        SessionFlowNotifier.new);
