import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/game_mode.dart';
import '../theme/app_theme.dart';

class SelectGameModeScreen extends StatefulWidget {
  final GameMode? initialMode;

  const SelectGameModeScreen({super.key, this.initialMode});

  @override
  State<SelectGameModeScreen> createState() => _SelectGameModeScreenState();
}

class _SelectGameModeScreenState extends State<SelectGameModeScreen> {
  GameType? _selectedType;
  String? _selectedVariantId;
  Map<String, dynamic> _settings = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialMode != null) {
      _selectedType = widget.initialMode!.type;
      _selectedVariantId = widget.initialMode!.variantId;
      _settings = Map.from(widget.initialMode!.settings);
    }
  }

  GameModeOptions? get _currentOptions {
    if (_selectedType == null) return null;
    return GameModeOptions.allOptions.firstWhere(
      (o) => o.type == _selectedType,
    );
  }

  void _selectType(GameType type) {
    setState(() {
      _selectedType = type;
      _selectedVariantId = null;
      _settings = {};
      
      // Se il gioco ha varianti, pre-seleziona la prima
      final options = GameModeOptions.allOptions.firstWhere((o) => o.type == type);
      if (options.variants.isNotEmpty) {
        _selectedVariantId = options.variants.first.id;
      }
      
      // Imposta i valori di default per le impostazioni
      for (final setting in options.settings) {
        _settings[setting.id] = setting.defaultValue;
      }
    });
  }

  void _confirm() {
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona una modalità di gioco'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    final gameMode = GameMode(
      type: _selectedType!,
      variantId: _selectedVariantId,
      settings: _settings,
    );

    Navigator.pop(context, gameMode);
  }

  void _showRules(GameMode mode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.primaryGreen,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.cream.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    mode.icon,
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      mode.displayName,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.gold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppTheme.cream),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Text(
                    mode.fullRules,
                    style: GoogleFonts.lato(
                      fontSize: 15,
                      color: AppTheme.cream,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scegli il Gioco'),
      ),
      body: ChristmasBackground(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Quale gioco volete fare?',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.cream,
                      ),
                      textAlign: TextAlign.center,
                    ).animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: -0.2, end: 0),
                    
                    const SizedBox(height: 8),
                    
                    Text(
                      'Seleziona una modalità per avere regole e impostazioni predefinite',
                      style: GoogleFonts.lato(
                        fontSize: 14,
                        color: AppTheme.cream.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ).animate()
                      .fadeIn(delay: 100.ms, duration: 400.ms),
                    
                    const SizedBox(height: 24),
                    
                    // Lista dei giochi
                    ...GameType.values.asMap().entries.map((entry) {
                      final index = entry.key;
                      final type = entry.value;
                      final tempMode = GameMode(type: type);
                      final isSelected = _selectedType == type;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: isSelected 
                            ? AppTheme.gold.withValues(alpha: 0.2)
                            : AppTheme.primaryGreen.withValues(alpha: 0.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSelected 
                                ? AppTheme.gold 
                                : AppTheme.gold.withValues(alpha: 0.3),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () => _selectType(type),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Text(
                                  tempMode.icon,
                                  style: const TextStyle(fontSize: 36),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tempMode.displayName,
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected 
                                              ? AppTheme.gold 
                                              : AppTheme.cream,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        tempMode.shortDescription,
                                        style: GoogleFonts.lato(
                                          fontSize: 12,
                                          color: AppTheme.cream.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _showRules(tempMode),
                                  icon: const Icon(Icons.info_outline),
                                  color: AppTheme.gold.withValues(alpha: 0.7),
                                  tooltip: 'Mostra regole',
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle,
                                    color: AppTheme.gold,
                                  )
                                else
                                  Icon(
                                    Icons.radio_button_unchecked,
                                    color: AppTheme.cream.withValues(alpha: 0.3),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ).animate(delay: Duration(milliseconds: 50 * index))
                        .fadeIn(duration: 300.ms)
                        .slideX(begin: 0.1, end: 0);
                    }),
                    
                    // Varianti (se il gioco ne ha)
                    if (_currentOptions != null && _currentOptions!.variants.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      
                      Text(
                        'Variante',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.gold,
                        ),
                      ).animate()
                        .fadeIn(duration: 300.ms),
                      
                      const SizedBox(height: 12),
                      
                      ...(_currentOptions!.variants.asMap().entries.map((entry) {
                        final index = entry.key;
                        final variant = entry.value;
                        final isSelected = _selectedVariantId == variant.id;
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: isSelected 
                              ? AppTheme.accentRed.withValues(alpha: 0.3)
                              : AppTheme.darkGreen.withValues(alpha: 0.5),
                          child: InkWell(
                            onTap: () => setState(() => _selectedVariantId = variant.id),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Radio<String>(
                                    value: variant.id,
                                    groupValue: _selectedVariantId,
                                    onChanged: (v) => setState(() => _selectedVariantId = v),
                                    activeColor: AppTheme.gold,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          variant.name,
                                          style: GoogleFonts.lato(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected 
                                                ? AppTheme.gold 
                                                : AppTheme.cream,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          variant.description,
                                          style: GoogleFonts.lato(
                                            fontSize: 12,
                                            color: AppTheme.cream.withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ).animate(delay: Duration(milliseconds: 50 * index))
                          .fadeIn(duration: 300.ms)
                          .slideX(begin: -0.1, end: 0);
                      })),
                    ],
                    
                    // Impostazioni (se il gioco ne ha)
                    if (_currentOptions != null && _currentOptions!.settings.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      
                      Text(
                        'Impostazioni',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.gold,
                        ),
                      ).animate()
                        .fadeIn(duration: 300.ms),
                      
                      const SizedBox(height: 12),
                      
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: _currentOptions!.settings.map((setting) {
                              return _buildSettingWidget(setting);
                            }).toList(),
                          ),
                        ),
                      ).animate()
                        .fadeIn(duration: 300.ms),
                    ],
                    
                    const SizedBox(height: 100), // Spazio per il bottone
                  ],
                ),
              ),
            ),
            
            // Bottone conferma
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.darkGreen.withValues(alpha: 0),
                    AppTheme.darkGreen,
                  ],
                ),
              ),
              child: SafeArea(
                child: ElevatedButton.icon(
                  onPressed: _selectedType != null ? _confirm : null,
                  icon: const Icon(Icons.check),
                  label: Text(
                    _selectedType != null 
                        ? 'Conferma: ${GameMode(type: _selectedType!).displayName}'
                        : 'Seleziona una modalità',
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
              ),
            ).animate()
              .fadeIn(delay: 400.ms, duration: 400.ms)
              .slideY(begin: 0.2, end: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingWidget(GameModeSetting setting) {
    switch (setting.type) {
      case SettingType.toggle:
        return SwitchListTile(
          title: Text(
            setting.name,
            style: GoogleFonts.lato(color: AppTheme.cream),
          ),
          value: _settings[setting.id] ?? setting.defaultValue,
          onChanged: (value) {
            setState(() => _settings[setting.id] = value);
          },
          activeColor: AppTheme.gold,
        );
      
      case SettingType.number:
        final currentValue = _settings[setting.id] ?? setting.defaultValue;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  setting.name,
                  style: GoogleFonts.lato(color: AppTheme.cream),
                ),
              ),
              IconButton(
                onPressed: currentValue > (setting.minValue ?? 1)
                    ? () => setState(() => _settings[setting.id] = currentValue - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: AppTheme.gold,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$currentValue',
                  style: GoogleFonts.lato(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gold,
                  ),
                ),
              ),
              IconButton(
                onPressed: currentValue < (setting.maxValue ?? 10)
                    ? () => setState(() => _settings[setting.id] = currentValue + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                color: AppTheme.gold,
              ),
            ],
          ),
        );
      
      case SettingType.choice:
        return const SizedBox.shrink(); // TODO: implementare se necessario
    }
  }
}

