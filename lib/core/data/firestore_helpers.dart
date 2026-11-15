import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'company_repository.dart';

/// Case-insensitive order for names.
int compareByName(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

/// Runs a Firestore call, turning its errors into readable [DataFailure]s.
Future<T> guardFirestore<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on FirebaseException catch (e) {
    throw DataFailure(firestoreMessage(e));
  }
}

/// Turns a stream's errors into readable [DataFailure]s.
Stream<T> friendlyErrors<T>(Stream<T> stream) => stream.transform(
  StreamTransformer.fromHandlers(
    handleError: (error, stackTrace, sink) => sink.addError(
      error is DataFailure ? error : DataFailure(firestoreMessage(error)),
      stackTrace,
    ),
  ),
);

String firestoreMessage(Object error) {
  final code = error is FirebaseException ? error.code : null;
  return switch (code) {
    'permission-denied' => 'Access was refused by the server.',
    'unavailable' => 'No internet connection. Please try again.',
    'not-found' => 'This item no longer exists.',
    null => 'Something went wrong. Please try again.',
    _ => 'Something went wrong ($code). Please try again.',
  };
}
