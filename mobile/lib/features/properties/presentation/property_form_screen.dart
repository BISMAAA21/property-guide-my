import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/presentation/async_state_widgets.dart';
import '../application/property_providers.dart';
import '../domain/property_listing.dart';

class PropertyFormScreen extends ConsumerStatefulWidget {
  const PropertyFormScreen({this.propertyId, super.key});

  final String? propertyId;

  @override
  ConsumerState<PropertyFormScreen> createState() => _PropertyFormScreenState();
}

class _PropertyFormScreenState extends ConsumerState<PropertyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _rent = TextEditingController();
  final _bedrooms = TextEditingController();
  final _bathrooms = TextEditingController();
  final _description = TextEditingController();
  final _facilities = TextEditingController();
  PropertyType _propertyType = PropertyType.apartment;
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.propertyId != null;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _rent.dispose();
    _bedrooms.dispose();
    _bathrooms.dispose();
    _description.dispose();
    _facilities.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEditing) return _buildForm(context);
    final repository = ref.watch(propertyRepositoryProvider);
    return StreamBuilder<PropertyListing?>(
      stream: repository.watchListing(widget.propertyId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: AsyncLoadingView(label: 'Loading listing form'),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit listing')),
            body: AsyncErrorView(
              error: snapshot.error,
              fallback: 'The listing could not be loaded for editing.',
            ),
          );
        }
        if (snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit listing')),
            body: const AsyncEmptyView(
              message: 'Listing not found.',
              icon: Icons.home_work_outlined,
            ),
          );
        }
        if (!_initialized) {
          _initialize(snapshot.data!);
        }
        return _buildForm(context);
      },
    );
  }

  Widget _buildForm(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit listing' : 'Create listing'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Property name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? 'Enter at least 3 characters.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _location,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Location in Malaysia',
                  hintText: 'e.g. Cyberjaya, Selangor',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? 'Enter the property location.'
                    : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rent,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Monthly rent (RM)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (double.tryParse(value ?? '') ?? 0) <= 0
                          ? 'Enter rent.'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<PropertyType>(
                      initialValue: _propertyType,
                      decoration: const InputDecoration(
                        labelText: 'Property type',
                        border: OutlineInputBorder(),
                      ),
                      items: PropertyType.values
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type.displayName),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => setState(
                        () => _propertyType = value ?? _propertyType,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _bedrooms,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Bedrooms',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          int.tryParse(value ?? '') == null ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _bathrooms,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Bathrooms',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (int.tryParse(value ?? '') ?? 0) < 1
                          ? 'At least 1'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _description,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  helperText: 'At least 20 characters',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 20
                    ? 'Add more property detail.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _facilities,
                decoration: const InputDecoration(
                  labelText: 'Facilities',
                  hintText: 'Wi-Fi, gym, study area',
                  helperText: 'Separate facilities with commas',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isEditing ? 'Save changes' : 'Save draft'),
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 8),
                const Text(
                  'After saving, add listing images before submitting the draft for administrator review.',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _initialize(PropertyListing listing) {
    _initialized = true;
    _name.text = listing.propertyName;
    _location.text = listing.location;
    _rent.text = listing.monthlyRent.toStringAsFixed(0);
    _bedrooms.text = listing.bedrooms.toString();
    _bathrooms.text = listing.bathrooms.toString();
    _description.text = listing.description;
    _facilities.text = listing.facilities.join(', ');
    _propertyType = listing.propertyType;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final input = PropertyWriteInput(
      propertyName: _name.text,
      location: _location.text,
      monthlyRent: double.parse(_rent.text),
      bedrooms: int.parse(_bedrooms.text),
      bathrooms: int.parse(_bathrooms.text),
      propertyType: _propertyType,
      description: _description.text,
      facilities: _facilities.text.split(','),
    );
    try {
      final repository = ref.read(propertyRepositoryProvider);
      final propertyId =
          widget.propertyId ?? await repository.createListing(input);
      if (_isEditing) await repository.updateListing(propertyId, input);
      if (mounted) context.go('/agent/properties/$propertyId');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingErrorMessage(
            error,
            fallback: 'The property could not be saved.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
