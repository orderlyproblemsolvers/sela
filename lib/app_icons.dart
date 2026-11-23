import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Centralized icon registry for Sela.
/// Swap any icon here to update it across every screen automatically.
class AppIcons {
  AppIcons._();

  // Navigation & Drawer
  static const IconData menu = LucideIcons.menu;
  static const IconData notes = LucideIcons.lightbulb;
  static const IconData notesSelected = LucideIcons.lightbulb;
  static const IconData archive = LucideIcons.archive;
  static const IconData archiveSelected = LucideIcons.archive;
  static const IconData unarchive = LucideIcons.archiveRestore;
  static const IconData trash = LucideIcons.trash2;
  static const IconData trashSelected = LucideIcons.trash2;
  static const IconData settings = LucideIcons.settings;
  static const IconData settingsSelected = LucideIcons.settings;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData check = LucideIcons.check;

  // Theme
  static const IconData themeSystem = LucideIcons.monitorSmartphone;
  static const IconData themeLight = LucideIcons.sun;
  static const IconData themeDark = LucideIcons.moon;

  // Notes & Actions
  static const IconData add = LucideIcons.plus;
  static const IconData addCircle = LucideIcons.circlePlus;
  static const IconData search = LucideIcons.search;
  static const IconData searchOff = LucideIcons.searchX;
  static const IconData close = LucideIcons.x;
  static const IconData more = LucideIcons.ellipsis;
  static const IconData pin = LucideIcons.pin;
  static const IconData unpin = LucideIcons.pinOff;
  static const IconData arrowUp = LucideIcons.arrowUp;
  static const IconData arrowDown = LucideIcons.arrowDown;
  static const IconData notesList = LucideIcons.alignLeft;
  static const IconData restore = LucideIcons.rotateCcw;
  static const IconData deleteForever = LucideIcons.trash2;

  // Selection
  static const IconData checked = LucideIcons.circleCheck;
  static const IconData unchecked = LucideIcons.circle;

  // Bible & Editor
  static const IconData bible = LucideIcons.bookOpen;
  static const IconData compare = LucideIcons.arrowLeftRight;
  static const IconData translate = LucideIcons.languages;
  static const IconData unfoldLess = LucideIcons.chevronsDownUp;
  static const IconData unfoldMore = LucideIcons.chevronsUpDown;
  static const IconData linkOff = LucideIcons.unlink;
  static const IconData tag = LucideIcons.hash;
  static const IconData exportFile = LucideIcons.share;
  static const IconData exportMarkdown = LucideIcons.fileText;
  static const IconData exportPdf = LucideIcons.fileType;

  // Backup & Security
  static const IconData uploadFile = LucideIcons.fileUp;
  static const IconData download = LucideIcons.download;
  static const IconData noteAdd = LucideIcons.filePlus;
  static const IconData lock = LucideIcons.lock;

  // Folders
  static const IconData folder = LucideIcons.folder;
  static const IconData folderOpen = LucideIcons.folderOpen;
  static const IconData folderPlus = LucideIcons.folderPlus;
  static const IconData folderOutput = LucideIcons.folderOutput;
}