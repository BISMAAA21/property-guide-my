class InspectionChecklistItem {
  const InspectionChecklistItem({
    required this.id,
    required this.sectionId,
    required this.title,
    required this.guidance,
  });

  final String id;
  final String sectionId;
  final String title;
  final String guidance;
}

class InspectionChecklistSection {
  const InspectionChecklistSection({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<InspectionChecklistItem> items;
}

abstract final class InspectionChecklist {
  static const version = '1.0.0';

  static const sections = <InspectionChecklistSection>[
    InspectionChecklistSection(
      id: 'living_room',
      title: 'Living room',
      items: [
        InspectionChecklistItem(
          id: 'living_walls_ceiling',
          sectionId: 'living_room',
          title: 'Walls and ceiling',
          guidance: 'Look for cracks, damp marks, mold, peeling paint, or recent patching.',
        ),
        InspectionChecklistItem(
          id: 'living_windows_doors',
          sectionId: 'living_room',
          title: 'Windows and doors',
          guidance: 'Open, close, and lock each accessible window and door.',
        ),
        InspectionChecklistItem(
          id: 'living_floor_furniture',
          sectionId: 'living_room',
          title: 'Floor and supplied furniture',
          guidance: 'Check for damage, instability, stains, or items missing from the listing.',
        ),
      ],
    ),
    InspectionChecklistSection(
      id: 'bedroom',
      title: 'Bedroom',
      items: [
        InspectionChecklistItem(
          id: 'bedroom_walls_ceiling',
          sectionId: 'bedroom',
          title: 'Walls and ceiling',
          guidance: 'Check corners and areas near windows for dampness, cracks, or mold.',
        ),
        InspectionChecklistItem(
          id: 'bedroom_windows_locks',
          sectionId: 'bedroom',
          title: 'Windows, door, and locks',
          guidance:
              'Confirm privacy, ventilation, and that locks operate correctly.',
        ),
        InspectionChecklistItem(
          id: 'bedroom_storage_furniture',
          sectionId: 'bedroom',
          title: 'Storage and furniture',
          guidance: 'Inspect the bed, mattress, desk, wardrobe, and other supplied items.',
        ),
      ],
    ),
    InspectionChecklistSection(
      id: 'bathroom',
      title: 'Bathroom',
      items: [
        InspectionChecklistItem(
          id: 'bathroom_water_drainage',
          sectionId: 'bathroom',
          title: 'Water pressure and drainage',
          guidance: 'Run taps and the shower, then confirm water drains without backing up.',
        ),
        InspectionChecklistItem(
          id: 'bathroom_toilet_leaks',
          sectionId: 'bathroom',
          title: 'Toilet and leaks',
          guidance: 'Flush the toilet and look below fixtures for active or historic leaks.',
        ),
        InspectionChecklistItem(
          id: 'bathroom_ventilation_mold',
          sectionId: 'bathroom',
          title: 'Ventilation and mold',
          guidance: 'Check the fan or window and inspect grout, seals, and corners for mold.',
        ),
      ],
    ),
    InspectionChecklistSection(
      id: 'kitchen',
      title: 'Kitchen',
      items: [
        InspectionChecklistItem(
          id: 'kitchen_sink_plumbing',
          sectionId: 'kitchen',
          title: 'Sink and plumbing',
          guidance: 'Run the tap and check the sink, drain, and cabinet below for leaks.',
        ),
        InspectionChecklistItem(
          id: 'kitchen_appliances',
          sectionId: 'kitchen',
          title: 'Supplied appliances',
          guidance: 'Confirm supplied appliances power on and note visible damage or missing parts.',
        ),
        InspectionChecklistItem(
          id: 'kitchen_storage_pests',
          sectionId: 'kitchen',
          title: 'Storage and pest signs',
          guidance: 'Open cupboards and look for cleanliness, damage, droppings, or insects.',
        ),
      ],
    ),
    InspectionChecklistSection(
      id: 'utilities',
      title: 'Utilities',
      items: [
        InspectionChecklistItem(
          id: 'utilities_water_electricity',
          sectionId: 'utilities',
          title: 'Water and electricity supply',
          guidance: 'Confirm both supplies are active and ask how meter readings and bills work.',
        ),
        InspectionChecklistItem(
          id: 'utilities_sockets_lights',
          sectionId: 'utilities',
          title: 'Sockets and lights',
          guidance: 'Test accessible lights and visually inspect sockets for damage or scorch marks.',
        ),
        InspectionChecklistItem(
          id: 'utilities_internet_cooling',
          sectionId: 'utilities',
          title: 'Internet and cooling',
          guidance: 'Confirm internet arrangements and test supplied fans or air conditioning.',
        ),
      ],
    ),
    InspectionChecklistSection(
      id: 'safety',
      title: 'Safety',
      items: [
        InspectionChecklistItem(
          id: 'safety_access_locks',
          sectionId: 'safety',
          title: 'Access and locks',
          guidance: 'Check entrance locks, access cards, gates, and shared-area security.',
        ),
        InspectionChecklistItem(
          id: 'safety_fire_equipment',
          sectionId: 'safety',
          title: 'Fire equipment',
          guidance: 'Locate smoke alarms, extinguishers, hose reels, and marked emergency exits.',
        ),
        InspectionChecklistItem(
          id: 'safety_hazards_exits',
          sectionId: 'safety',
          title: 'Hazards and escape route',
          guidance: 'Look for loose rails, trip hazards, blocked exits, or unsafe exposed wiring.',
        ),
      ],
    ),
  ];

  static List<InspectionChecklistItem> get items =>
      List.unmodifiable(sections.expand((section) => section.items));

  static InspectionChecklistItem? itemById(String id) =>
      items.where((item) => item.id == id).firstOrNull;

  static InspectionChecklistSection? sectionById(String id) =>
      sections.where((section) => section.id == id).firstOrNull;
}
