import 'dart:convert';

/// One write the app made that the network refused to carry.
///
/// **It is data, not a closure.** That is the whole design decision in this
/// file: a queue of callbacks cannot survive the process, and §Phase 9 asks
/// for work that is not lost "on a weak atoll connection" — which includes
/// the connection dropping and Android reclaiming the app while it is
/// backgrounded. A request that is `{method, path, body}` can be written to
/// disk and re-issued on the next launch; a `Future Function()` cannot.
///
/// It also keeps the queue honest about what it is allowed to hold: three
/// surfaces queue and no others (§0.0 item 14 — the wizard's autosave, the
/// slot/request accept prompt, chat sends), and each one is a plain HTTP call
/// with a JSON body.
class PendingRequest {
  const PendingRequest({
    required this.id,
    required this.method,
    required this.path,
    required this.label,
    required this.mergeKey,
    this.body,
    this.idempotencyKey,
  });

  factory PendingRequest.fromJson(Map<String, dynamic> json) => PendingRequest(
    id: json['id'] as String,
    method: json['method'] as String,
    path: json['path'] as String,
    label: json['label'] as String? ?? '',
    mergeKey: json['mergeKey'] as String? ?? json['id'] as String,
    body: json['body'] as Map<String, dynamic>?,
    idempotencyKey: json['idempotencyKey'] as String?,
  );

  /// Stable per queued item, so a replay can remove exactly the one it sent.
  final String id;

  /// `PATCH`, `POST` or `DELETE`. Never `GET` — a read that failed is
  /// retried by the screen that wanted it, not replayed later against state
  /// that has moved on.
  final String method;
  final String path;

  /// What the offline screen calls this, in the provider's words:
  /// "Saving a step of the service wizard".
  final String label;

  /// Two queued requests with the same key are **the same intention stated
  /// twice**, and only the newer one should reach the server. Ten keystrokes
  /// on the service name while offline are one PATCH, not ten — and a `PATCH`
  /// is a partial update, so merging bodies key-by-key is exactly right.
  ///
  /// A `POST` sets a key unique to itself, so nothing ever merges two
  /// creations.
  final String mergeKey;

  final Map<String, dynamic>? body;

  /// Required by the server on every creating call (§1a), and the reason a
  /// replay is safe: a request that in fact arrived before the connection
  /// dropped returns its original answer instead of creating a second row.
  final String? idempotencyKey;

  /// [other] is newer. Bodies merge key-by-key with the newer value winning;
  /// everything else comes from the newer request.
  PendingRequest mergedWith(PendingRequest other) => PendingRequest(
    id: other.id,
    method: other.method,
    path: other.path,
    label: other.label,
    mergeKey: other.mergeKey,
    body: body == null && other.body == null
        ? null
        : {...?body, ...?other.body},
    idempotencyKey: other.idempotencyKey ?? idempotencyKey,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    'path': path,
    'label': label,
    'mergeKey': mergeKey,
    if (body != null) 'body': body,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
  };

  static String encode(List<PendingRequest> queue) =>
      jsonEncode([for (final r in queue) r.toJson()]);

  /// Anything unreadable decodes to an empty queue rather than throwing. A
  /// half-written file from a process killed mid-flush must not stop the app
  /// starting — losing the queue is bad, failing to launch is worse.
  static List<PendingRequest> decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded.whereType<Map<String, dynamic>>())
          PendingRequest.fromJson(entry),
      ];
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }
}

/// A queued write the **server** refused — not a connection problem.
///
/// It leaves the queue (retrying it forever would never succeed) and lands
/// here so the screen that owns it can say so. frontend/CLAUDE.md: never
/// silently discard user input, and a rejection the user is never told about
/// is a discard.
class RejectedRequest {
  const RejectedRequest({required this.request, required this.message});
  final PendingRequest request;
  final String message;
}
