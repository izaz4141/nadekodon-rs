import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/logger.dart';

class LicensesDialog extends StatefulWidget {
  const LicensesDialog({super.key});

  @override
  State<LicensesDialog> createState() => _LicensesDialogState();
}

class _LicensesDialogState extends State<LicensesDialog> {
  final Map<String, List<LicenseEntry>> _packageLicenses = {};
  final List<String> _packages = [];
  bool _isLoading = true;
  String? _selectedPackage;
  PackageInfo? _packageInfo;
  bool _viewingDetail = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final packageInfo = await PackageInfo.fromPlatform();

    // Collect licenses and group by package
    await for (final license in LicenseRegistry.licenses) {
      for (final package in license.packages) {
        if (!_packageLicenses.containsKey(package)) {
          _packageLicenses[package] = [];
        }
        _packageLicenses[package]!.add(license);
      }
    }

    // Load Rust licenses
    try {
      final jsonString = await rootBundle.loadString(
        'assets/licenses/cargo_licenses.json',
      );
      final List<dynamic> jsonList = json.decode(jsonString);
      for (final item in jsonList) {
        final name = item['name'] as String;
        final version = item['version'] as String;
        final licenseType = item['license'] as String?;
        final repository = item['repository'] as String?;
        final description = item['description'] as String?;
        final authors = item['authors'] as String?;

        final StringBuffer licenseTextBuffer = StringBuffer();
        if (description != null) {
          licenseTextBuffer.writeln(description);
          licenseTextBuffer.writeln();
        }
        if (repository != null) {
          licenseTextBuffer.writeln('Repository: $repository');
        }
        if (authors != null) {
          licenseTextBuffer.writeln(
            'Authors: ${authors.replaceAll('|', ', ')}',
          );
        }
        licenseTextBuffer.writeln('\nVersion: $version');
        if (licenseType != null) {
          licenseTextBuffer.writeln('\nLicense: $licenseType');
        }

        final licenseEntry = LicenseEntryWithLineBreaks([
          name,
        ], licenseTextBuffer.toString());

        if (!_packageLicenses.containsKey(name)) {
          _packageLicenses[name] = [];
        }
        _packageLicenses[name]!.add(licenseEntry);
      }
    } catch (e) {
      log('Failed to load Rust licenses: $e', isError: true);
    }

    // Sort packages
    _packages.addAll(_packageLicenses.keys);
    _packages.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (mounted) {
      setState(() {
        _packageInfo = packageInfo;
        _isLoading = false;
        if (_packages.isNotEmpty) {
          _selectedPackage = _packages.first;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final isDesktop = AppTheme.isDesktop(context);

    final listWidget = SizedBox(
      width: isDesktop ? 250 : double.infinity,
      child: Column(
        children: [
          if (_packageInfo != null) ...[
            Text(
              "Nadeko~don",
              style: textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            SvgPicture.asset(
              'assets/icons/nadeko-don-filled.svg',
              width: AppTheme.iconXXL * AppTheme.iconScale(context),
              height: AppTheme.iconXXL * AppTheme.iconScale(context),
              colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
            ),
            Text(
              '${_packageInfo!.version}+${_packageInfo!.buildNumber}',
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spaceMD),
            Text(
              "Glicole",
              style: textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spaceMD),
            Text(
              "AGPL-3.0",
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spaceXS),
            const Divider(),
          ],
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _packages.length,
              itemBuilder: (context, index) {
                final packageName = _packages[index];
                final isSelected = _selectedPackage == packageName;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedPackage = packageName;
                      if (!isDesktop) {
                        _viewingDetail = true;
                      }
                    });
                  },
                  child: Container(
                    color: isSelected ? colors.primaryContainer : null,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTheme.spaceSM,
                      horizontal: AppTheme.spaceMD,
                    ),
                    child: Text(
                      packageName,
                      style: TextStyle(
                        fontSize: AppTheme.textSM,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? colors.onPrimaryContainer : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    final detailWidget = Expanded(
      child: _selectedPackage == null
          ? Center(
              child: Text(
                'Select a package to view license',
                style: textTheme.bodyMedium,
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(AppTheme.spaceMD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_selectedPackage!, style: textTheme.titleMedium),
                  const SizedBox(height: AppTheme.spaceSM),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                      ),
                      padding: const EdgeInsets.all(AppTheme.spaceSM),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ..._packageLicenses[_selectedPackage]!.map((
                              license,
                            ) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppTheme.spaceSM,
                                ),
                                child: Text(
                                  license.paragraphs
                                      .map((p) => p.text)
                                      .join('\n\n'),
                                  style: textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );

    Widget titleWidget;
    if (!isDesktop && _viewingDetail) {
      titleWidget = Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              setState(() {
                _viewingDetail = false;
              });
            },
          ),
          const SizedBox(width: AppTheme.spaceSM),
          Expanded(
            child: Text(
              'License',
              style: textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else {
      titleWidget = Text('Licenses', style: textTheme.titleLarge);
    }

    return PopScope(
      canPop: isDesktop || !_viewingDetail,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!isDesktop && _viewingDetail) {
          setState(() {
            _viewingDetail = false;
          });
        }
      },
      child: AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: titleWidget),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: double.maxFinite,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    listWidget,
                    const VerticalDivider(width: 1),
                    detailWidget,
                  ],
                )
              : IndexedStack(
                  index: _viewingDetail ? 1 : 0,
                  children: [
                    listWidget,
                    Column(children: [detailWidget]),
                  ],
                ),
        ),
      ),
    );
  }
}
