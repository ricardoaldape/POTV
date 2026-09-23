import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/youtube_models.dart';
import 'youtube_client.dart';
import 'youtube_subscription_repository.dart';

final youtubeSubscriptionFeedProvider = FutureProvider<List<PotvYoutubeVideo>>((ref) async {
  final subscriptions = await ref.watch(youtubeSubscriptionsProvider.future);
  return ref.read(potvYoutubeClientProvider).subscriptionFeed(subscriptions);
});
