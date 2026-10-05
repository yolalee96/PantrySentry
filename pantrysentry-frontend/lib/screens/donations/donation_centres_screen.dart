import 'package:flutter/material.dart';

import '../../models/donation.dart';
import '../../services/location_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'donation_centre_screen.dart';

/// Epic 7 / User Story 7.1 — find donation centres. With [items] (coming
/// from "Donate food"), centres are checked against those items and the
/// ones that take most of them come first, then the nearest. Without
/// items it's a plain "browse centres" list.
class DonationCentresScreen extends StatefulWidget {
  const DonationCentresScreen({super.key, required this.appState, this.items = const []});
  final AppState appState;
  final List<DonatableItem> items;

  @override
  State<DonationCentresScreen> createState() => _DonationCentresScreenState();
}

class _DonationCentresScreenState extends State<DonationCentresScreen> {
  final _areaController = TextEditingController();
  List<DonationCentre>? _centres;
  String? _error;
  String? _locationProblem;
  bool _loading = false;
  bool _locating = false;
  double? _lat;
  double? _lng;
  String _query = '';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _areaController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final centres = await widget.appState.getDonationCentres(
        latitude: _lat,
        longitude: _lng,
        query: _query,
        itemIds: widget.items.map((i) => i.id).toList(),
      );
      if (!mounted || id != _request) return;
      setState(() {
        _centres = centres;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// AC 7.1.2–7.1.4.
  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locationProblem = null;
    });
    final result = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (result.ok) {
        _lat = result.latitude;
        _lng = result.longitude;
        _query = '';
        _areaController.clear();
      } else {
        _locationProblem = result.problem;
      }
    });
    if (result.ok) _search();
  }

  /// AC 7.1.5.
  void _searchArea() {
    setState(() => _query = _areaController.text.trim());
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = widget.items.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(hasItems ? 'Choose a centre' : 'Donation centres')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // AC 7.1.1 — both options up front.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _areaController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchArea(),
                  decoration: const InputDecoration(
                    hintText: 'Area, city or postcode',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(onPressed: _searchArea, child: const Text('Search')),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _locating ? null : _useMyLocation,
            icon: _locating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_lat != null ? Icons.my_location : Icons.location_searching),
            label: Text(_lat != null ? 'Using your location · refresh' : 'Use my location'),
          ),
          if (_locationProblem != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_locationProblem!, style: const TextStyle(color: AppTheme.paprika, fontSize: 12.5)),
            ),
          const SizedBox(height: 12),
          if (hasItems)
            Text(
              'Centres that take more of your ${widget.items.length} ${widget.items.length == 1 ? 'item' : 'items'} come first'
              '${_lat != null ? ', then the nearest' : ''}.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          if (_loading && _centres == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (_loading && _centres != null) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (_centres != null && _centres!.isEmpty)
            // AC 7.1.8
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 40, color: Colors.grey.shade500),
                  const SizedBox(height: 8),
                  Text(_query.isEmpty ? 'No donation centres found.' : 'No donation centres found for "$_query".',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Try another area, a city or state name, or use your location.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
            ),
          for (final centre in _centres ?? const <DonationCentre>[]) ...[
            const SizedBox(height: 10),
            _CentreCard(
              centre: centre,
              itemCount: widget.items.length,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DonationCentreScreen(appState: widget.appState, centre: centre, items: widget.items),
              )),
            ),
          ],
        ],
      ),
    );
  }
}

class _CentreCard extends StatelessWidget {
  const _CentreCard({required this.centre, required this.itemCount, required this.onTap});
  final DonationCentre centre;
  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final covered = centre.listedItemCount + centre.similarItemCount;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(centre.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
                  // AC 7.1.6 — approximate distance where location allows.
                  if (centre.distanceKm != null)
                    Text('${centre.distanceKm!.toStringAsFixed(1)} km',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.ocean)),
                ],
              ),
              const SizedBox(height: 2),
              Text(centre.typeLabel, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text(centre.fullAddress, style: const TextStyle(fontSize: 12.5)),
              if (centre.operatingHours != null) ...[
                const SizedBox(height: 4),
                Text(centre.operatingHours!, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
              if (itemCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  centre.acceptedFoods.isEmpty
                      ? 'No food list published — contact them first'
                      : covered == 0
                          ? 'None of your items are on their list'
                          : 'Takes $covered of your $itemCount ${itemCount == 1 ? 'item' : 'items'}'
                              '${centre.similarItemCount > 0 ? ' (${centre.similarItemCount} similar)' : ''}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: covered == 0 ? AppTheme.paprika : AppTheme.seedColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
