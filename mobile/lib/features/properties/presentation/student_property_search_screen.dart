import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/async_state_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../application/property_providers.dart';
import '../domain/property_listing.dart';

class StudentPropertySearchScreen extends ConsumerStatefulWidget {
  const StudentPropertySearchScreen({super.key});

  @override
  ConsumerState<StudentPropertySearchScreen> createState() =>
      _StudentPropertySearchScreenState();
}

class _StudentPropertySearchScreenState
    extends ConsumerState<StudentPropertySearchScreen> {
  late final Stream<List<PropertyListing>> _listingsStream;
  final _queryController = TextEditingController();
  final _locationController = TextEditingController();
  double? _minimumRent;
  double? _maximumRent;
  double? _minimumRating;
  PropertySortOrder _sortOrder = PropertySortOrder.newest;

  PropertySearchFilter get _filter => PropertySearchFilter(
    query: _queryController.text,
    location: _locationController.text,
    minimumRent: _minimumRent,
    maximumRent: _maximumRent,
    minimumRating: _minimumRating,
    sortOrder: _sortOrder,
  );

  bool get _hasAdvancedFilters =>
      _locationController.text.trim().isNotEmpty ||
      _minimumRent != null ||
      _maximumRent != null ||
      _minimumRating != null ||
      _sortOrder != PropertySortOrder.newest;

  @override
  void initState() {
    super.initState();
    _listingsStream = ref
        .read(propertyRepositoryProvider)
        .watchApprovedListings();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.snapshot.user!;
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF7),
      appBar: AppBar(
        title: const Text('Find a home'),
        actions: [
          IconButton(
            key: const Key('open_agreements_button'),
            tooltip: 'Understand an agreement',
            onPressed: () => context.push('/student/agreements'),
            icon: const Icon(Icons.document_scanner_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: auth.isBusy ? null : auth.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<List<PropertyListing>>(
        stream: _listingsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AsyncLoadingView(label: 'Loading approved properties');
          }
          if (snapshot.hasError) {
            return AsyncErrorView(
              error: snapshot.error,
              fallback: 'Approved properties could not be loaded.',
            );
          }
          final listings = _filter.apply(snapshot.data ?? const []);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              Text(
                'Welcome, ${user.name}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Compare administrator-approved rentals for international students.',
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('property_search_field'),
                controller: _queryController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Search properties',
                  hintText: 'Name, description, or location',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _queryController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _queryController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('property_filter_button'),
                      onPressed: _showFilters,
                      icon: const Icon(Icons.tune),
                      label: Text(
                        _hasAdvancedFilters ? 'Filters applied' : 'Filters',
                      ),
                    ),
                  ),
                  if (_hasAdvancedFilters) ...[
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Clear filters',
                      onPressed: _clearAdvancedFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${listings.length} approved ${listings.length == 1 ? 'property' : 'properties'}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(_sortOrder.label),
                ],
              ),
              const SizedBox(height: 10),
              if (listings.isEmpty)
                const _SearchEmptyState()
              else
                ...listings.map(
                  (listing) => _StudentPropertyCard(
                    listing: listing,
                    onTap: () =>
                        context.push('/student/properties/${listing.id}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showFilters() async {
    final minimumController = TextEditingController(
      text: _minimumRent?.toStringAsFixed(0) ?? '',
    );
    final maximumController = TextEditingController(
      text: _maximumRent?.toStringAsFixed(0) ?? '',
    );
    final locationController = TextEditingController(
      text: _locationController.text,
    );
    var rating = _minimumRating;
    var sort = _sortOrder;
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Filter approved properties',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('location_filter_field'),
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    hintText: 'For example, Cyberjaya',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minimumController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minimum rent',
                          prefixText: 'RM ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: maximumController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Maximum rent',
                          prefixText: 'RM ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<double?>(
                  initialValue: rating,
                  decoration: const InputDecoration(
                    labelText: 'Minimum rating',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Any rating')),
                    DropdownMenuItem(
                      value: 3,
                      child: Text('3 stars and above'),
                    ),
                    DropdownMenuItem(
                      value: 4,
                      child: Text('4 stars and above'),
                    ),
                    DropdownMenuItem(
                      value: 4.5,
                      child: Text('4.5 stars and above'),
                    ),
                  ],
                  onChanged: (value) => setSheetState(() => rating = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PropertySortOrder>(
                  initialValue: sort,
                  decoration: const InputDecoration(
                    labelText: 'Sort by',
                    border: OutlineInputBorder(),
                  ),
                  items: PropertySortOrder.values
                      .map(
                        (order) => DropdownMenuItem(
                          value: order,
                          child: Text(order.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setSheetState(() => sort = value);
                  },
                ),
                const SizedBox(height: 18),
                FilledButton(
                  key: const Key('apply_property_filters'),
                  onPressed: () {
                    final minimum = _optionalNumber(minimumController.text);
                    final maximum = _optionalNumber(maximumController.text);
                    final candidate = PropertySearchFilter(
                      location: locationController.text,
                      minimumRent: minimum,
                      maximumRent: maximum,
                      minimumRating: rating,
                      sortOrder: sort,
                    );
                    final error = candidate.validate();
                    if (error != null) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(error)));
                      return;
                    }
                    Navigator.pop(
                      context,
                      _FilterResult(
                        location: locationController.text,
                        minimumRent: minimum,
                        maximumRent: maximum,
                        minimumRating: rating,
                        sortOrder: sort,
                      ),
                    );
                  },
                  child: const Text('Apply filters'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      minimumController.dispose();
      maximumController.dispose();
      locationController.dispose();
    });
    if (result == null || !mounted) return;
    setState(() {
      _locationController.text = result.location;
      _minimumRent = result.minimumRent;
      _maximumRent = result.maximumRent;
      _minimumRating = result.minimumRating;
      _sortOrder = result.sortOrder;
    });
  }

  static double? _optionalNumber(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized) ?? -1;
  }

  void _clearAdvancedFilters() {
    setState(() {
      _locationController.clear();
      _minimumRent = null;
      _maximumRent = null;
      _minimumRating = null;
      _sortOrder = PropertySortOrder.newest;
    });
  }
}

class _FilterResult {
  const _FilterResult({
    required this.location,
    required this.minimumRent,
    required this.maximumRent,
    required this.minimumRating,
    required this.sortOrder,
  });

  final String location;
  final double? minimumRent;
  final double? maximumRent;
  final double? minimumRating;
  final PropertySortOrder sortOrder;
}

class _StudentPropertyCard extends StatelessWidget {
  const _StudentPropertyCard({required this.listing, required this.onTap});

  final PropertyListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('student_property_${listing.id}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (listing.imageUrls.isEmpty)
              Container(
                height: 150,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Icon(Icons.home_work_outlined, size: 48),
              )
            else
              Image.network(
                listing.imageUrls.first,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 170,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          listing.propertyName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text(
                        'RM ${listing.monthlyRent.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(listing.location),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _CompactFact(
                        icon: Icons.bed_outlined,
                        label: '${listing.bedrooms} bed',
                      ),
                      _CompactFact(
                        icon: Icons.bathtub_outlined,
                        label: '${listing.bathrooms} bath',
                      ),
                      _CompactFact(
                        icon: Icons.star,
                        label: listing.ratingCount == 0
                            ? 'No reviews yet'
                            : '${listing.ratingAverage.toStringAsFixed(1)} (${listing.ratingCount})',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactFact extends StatelessWidget {
  const _CompactFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 17), const SizedBox(width: 4), Text(label)],
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Card(
      key: Key('property_empty_state'),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.search_off_outlined, size: 44),
            SizedBox(height: 10),
            Text('No approved properties match these filters.'),
            SizedBox(height: 4),
            Text('Try a different location, rent range, or rating.'),
          ],
        ),
      ),
    );
  }
}

extension on PropertySortOrder {
  String get label => switch (this) {
    PropertySortOrder.newest => 'Newest',
    PropertySortOrder.priceLowToHigh => 'Lowest rent',
    PropertySortOrder.priceHighToLow => 'Highest rent',
    PropertySortOrder.ratingHighToLow => 'Highest rated',
  };
}
