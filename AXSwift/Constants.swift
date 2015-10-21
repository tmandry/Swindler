/// All possible notifications you can subscribe to with `Observer`.
/// - seeAlso: [Notificatons](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/c/data/NSAccessibilityAnnouncementRequestedNotification)
public enum Notification: String {
  // Focus notifications
  case MainWindowChanged       = "AXMainWindowChanged"
  case FocusedWindowChanged    = "AXFocusedWindowChanged"
  case FocusedUIElementChanged = "AXFocusedUIElementChanged"

  // Application notifications
  case ApplicationActivated    = "AXApplicationActivated"
  case ApplicationDeactivated  = "AXApplicationDeactivated"
  case ApplicationHidden       = "AXApplicationHidden"
  case ApplicationShown        = "AXApplicationShown"

  // Window notifications
  case WindowCreated           = "AXWindowCreated"
  case WindowMoved             = "AXWindowMoved"
  case WindowResized           = "AXWindowResized"
  case WindowMiniaturized      = "AXWindowMiniaturized"
  case WindowDeminiaturized    = "AXWindowDeminiaturized"

  // Drawer & sheet notifications
  case DrawerCreated           = "AXDrawerCreated"
  case SheetCreated            = "AXSheetCreated"

  // Element notifications
  case UIElementDestroyed      = "AXUIElementDestroyed"
  case ValueChanged            = "AXValueChanged"
  case TitleChanged            = "AXTitleChanged"
  case Resized                 = "AXResized"
  case Moved                   = "AXMoved"
  case Created                 = "AXCreated"

  // Used when UI changes require the attention of assistive application.  Pass along a user info
  // dictionary with the key NSAccessibilityUIElementsKey and an array of elements that have been
  // added or changed as a result of this layout change.
  case LayoutChanged           = "AXLayoutChanged"

  // Misc notifications
  case HelpTagCreated          = "AXHelpTagCreated"
  case SelectedTextChanged     = "AXSelectedTextChanged"
  case RowCountChanged         = "AXRowCountChanged"
  case SelectedChildrenChanged = "AXSelectedChildrenChanged"
  case SelectedRowsChanged     = "AXSelectedRowsChanged"
  case SelectedColumnsChanged  = "AXSelectedColumnsChanged"

  case RowExpanded             = "AXRowExpanded"
  case RowCollapsed            = "AXRowCollapsed"

  // Cell-table notifications
  case SelectedCellsChanged    = "AXSelectedCellsChanged"

  // Layout area notifications
  case UnitsChanged            = "AXUnitsChanged"
  case SelectedChildrenMoved   = "AXSelectedChildrenMoved"

  // This notification allows an application to request that an announcement be made to the user by
  // an assistive application such as VoiceOver.  The notification requires a user info dictionary
  // with the key NSAccessibilityAnnouncementKey and the announcement as a localized string.  In
  // addition, the key NSAccessibilityAnnouncementPriorityKey should also be used to help an
  // assistive application determine the importance of this announcement.  This notification should
  // be posted for the application element.
  case AnnouncementRequested   = "AXAnnouncementRequested"
}

/// All UIElement roles.
/// - seeAlso: [Roles](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/doc/constant_group/Roles)
public enum Role: String {
  case Unknown            = "AXUnknown"
  case Button             = "AXButton"
  case RadioButton        = "AXRadioButton"
  case CheckBox           = "AXCheckBox"
  case Slider             = "AXSlider"
  case TabGroup           = "AXTabGroup"
  case TextField          = "AXTextField"
  case StaticText         = "AXStaticText"
  case TextArea           = "AXTextArea"
  case ScrollArea         = "AXScrollArea"
  case PopUpButton        = "AXPopUpButton"
  case MenuButton         = "AXMenuButton"
  case Table              = "AXTable"
  case Application        = "AXApplication"
  case Group              = "AXGroup"
  case RadioGroup         = "AXRadioGroup"
  case List               = "AXList"
  case ScrollBar          = "AXScrollBar"
  case ValueIndicator     = "AXValueIndicator"
  case Image              = "AXImage"
  case MenuBar            = "AXMenuBar"
  case Menu               = "AXMenu"
  case MenuItem           = "AXMenuItem"
  case Column             = "AXColumn"
  case Row                = "AXRow"
  case Toolbar            = "AXToolbar"
  case BusyIndicator      = "AXBusyIndicator"
  case ProgressIndicator  = "AXProgressIndicator"
  case Window             = "AXWindow"
  case Drawer             = "AXDrawer"
  case SystemWide         = "AXSystemWide"
  case Outline            = "AXOutline"
  case Incrementor        = "AXIncrementor"
  case Browser            = "AXBrowser"
  case ComboBox           = "AXComboBox"
  case SplitGroup         = "AXSplitGroup"
  case Splitter           = "AXSplitter"
  case ColorWell          = "AXColorWell"
  case GrowArea           = "AXGrowArea"
  case Sheet              = "AXSheet"
  case HelpTag            = "AXHelpTag"
  case Matte              = "AXMatte"
  case Ruler              = "AXRuler"
  case RulerMarker        = "AXRulerMarker"
  case Link               = "AXLink"
  case DisclosureTriangle = "AXDisclosureTriangle"
  case Grid               = "AXGrid"
  case RelevanceIndicator = "AXRelevanceIndicator"
  case LevelIndicator     = "AXLevelIndicator"
  case Cell               = "AXCell"
  case Popover            = "AXPopover"
  case LayoutArea         = "AXLayoutArea"
  case LayoutItem         = "AXLayoutItem"
  case Handle             = "AXHandle"
}

/// All UIElement subroles.
/// - seeAlso: [Subroles](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/doc/constant_group/Subroles)
public enum Subrole: String {
  case Unknown              = "AXUnknown"
  case CloseButton          = "AXCloseButton"
  case ZoomButton           = "AXZoomButton"
  case MinimizeButton       = "AXMinimizeButton"
  case ToolbarButton        = "AXToolbarButton"
  case TableRow             = "AXTableRow"
  case OutlineRow           = "AXOutlineRow"
  case SecureTextField      = "AXSecureTextField"
  case StandardWindow       = "AXStandardWindow"
  case Dialog               = "AXDialog"
  case SystemDialog         = "AXSystemDialog"
  case FloatingWindow       = "AXFloatingWindow"
  case SystemFloatingWindow = "AXSystemFloatingWindow"
  case IncrementArrow       = "AXIncrementArrow"
  case DecrementArrow       = "AXDecrementArrow"
  case IncrementPage        = "AXIncrementPage"
  case DecrementPage        = "AXDecrementPage"
  case SearchField          = "AXSearchField"
  case TextAttachment       = "AXTextAttachment"
  case TextLink             = "AXTextLink"
  case Timeline             = "AXTimeline"
  case SortButton           = "AXSortButton"
  case RatingIndicator      = "AXRatingIndicator"
  case ContentList          = "AXContentList"
  case DefinitionList       = "AXDefinitionList"
  case FullScreenButton     = "AXFullScreenButton"
  case Toggle               = "AXToggle"
  case Switch               = "AXSwitch"
  case DescriptionList      = "AXDescriptionList"
}

/// Orientations returned by the orientation property.
/// - seeAlso: [NSAccessibilityOrientation](https://developer.apple.com/library/mac/documentation/AppKit/Reference/NSAccessibility_Protocol_Reference/index.html#//apple_ref/c/tdef/NSAccessibilityOrientation)
public enum Orientation: Int {
   case Unknown    = 0
   case Vertical   = 1
   case Horizontal = 2
}

public enum Attribute: String {
  // Standard attributes
  case Role                                   = "AXRole" //(NSString *) - type, non-localized (e.g. radioButton)
  case RoleDescription                        = "AXRoleDescription" //(NSString *) - user readable role (e.g. "radio button")
  case Subrole                                = "AXSubrole" //(NSString *) - type, non-localized (e.g. closeButton)
  case Help                                   = "AXHelp" //(NSString *) - instance description (e.g. a tool tip)
  case Value                                  = "AXValue" //(id)         - element's value
  case MinValue                               = "AXMinValue" //(id)         - element's min value
  case MaxValue                               = "AXMaxValue" //(id)         - element's max value
  case Enabled                                = "AXEnabled" //(NSNumber *) - (boolValue) responds to user?
  case Focused                                = "AXFocused" //(NSNumber *) - (boolValue) has keyboard focus?
  case Parent                                 = "AXParent" //(id)         - element containing you
  case Children                               = "AXChildren" //(NSArray *)  - elements you contain
  case Window                                 = "AXWindow" //(id)         - UIElement for the containing window
  case TopLevelUIElement                      = "AXTopLevelUIElement" //(id)         - UIElement for the containing top level element
  case SelectedChildren                       = "AXSelectedChildren" //(NSArray *)  - child elements which are selected
  case VisibleChildren                        = "AXVisibleChildren" //(NSArray *)  - child elements which are visible
  case Position                               = "AXPosition" //(NSValue *)  - (pointValue) position in screen coords
  case Size                                   = "AXSize" //(NSValue *)  - (sizeValue) size
  case Frame                                  = "AXFrame" //(NSValue *)  - (rectValue) frame
  case Contents                               = "AXContents" //(NSArray *)  - main elements
  case Title                                  = "AXTitle" //(NSString *) - visible text (e.g. of a push button)
  case Description                            = "AXDescription" //(NSString *) - instance description
  case ShownMenu                              = "AXShownMenu" //(id)         - menu being displayed
  case ValueDescription                       = "AXValueDescription" //(NSString *)  - text description of value

  case SharedFocusElements                    = "AXSharedFocusElements" //(NSArray *)  - elements that share focus

  // Misc attributes
  case PreviousContents                       = "AXPreviousContents" //(NSArray *)  - main elements
  case NextContents                           = "AXNextContents" //(NSArray *)  - main elements
  case Header                                 = "AXHeader" //(id)         - UIElement for header.
  case Edited                                 = "AXEdited" //(NSNumber *) - (boolValue) is it dirty?
  case Tabs                                   = "AXTabs" //(NSArray *)  - UIElements for tabs
  case HorizontalScrollBar                    = "AXHorizontalScrollBar" //(id)       - UIElement for the horizontal scroller
  case VerticalScrollBar                      = "AXVerticalScrollBar" //(id)         - UIElement for the vertical scroller
  case OverflowButton                         = "AXOverflowButton" //(id)         - UIElement for overflow
  case IncrementButton                        = "AXIncrementButton" //(id)         - UIElement for increment
  case DecrementButton                        = "AXDecrementButton" //(id)         - UIElement for decrement
  case Filename                               = "AXFilename" //(NSString *) - filename
  case Expanded                               = "AXExpanded" //(NSNumber *) - (boolValue) is expanded?
  case Selected                               = "AXSelected" //(NSNumber *) - (boolValue) is selected?
  case Splitters                              = "AXSplitters" //(NSArray *)  - UIElements for splitters
  case Document                               = "AXDocument" //(NSString *) - url as string - for open document
  case ActivationPoint                        = "AXActivationPoint" //(NSValue *)  - (pointValue)

  case URL                                    = "AXURL" //(NSURL *)    - url
  case Index                                  = "AXIndex" //(NSNumber *)  - (intValue)

  case RowCount                               = "AXRowCount" //(NSNumber *)  - (intValue) number of rows

  case ColumnCount                            = "AXColumnCount" //(NSNumber *)  - (intValue) number of columns

  case OrderedByRow                           = "AXOrderedByRow" //(NSNumber *)  - (boolValue) is ordered by row?

  case WarningValue                           = "AXWarningValue" //(id)  - warning value of a level indicator, typically a number

  case CriticalValue                          = "AXCriticalValue" //(id)  - critical value of a level indicator, typically a number

  case PlaceholderValue                       = "AXPlaceholderValue" //(NSString *)  - placeholder value of a control such as a text field

  case ContainsProtectedContent               = "AXContainsProtectedContent" // (NSNumber *) - (boolValue) contains protected content?
  case AlternateUIVisible                     = "AXAlternateUIVisible" //(NSNumber *) - (boolValue)

  // Linkage attributes
  case TitleUIElement                         = "AXTitleUIElement" //(id)       - UIElement for the title
  case ServesAsTitleForUIElements             = "AXServesAsTitleForUIElements" //(NSArray *) - UIElements this titles
  case LinkedUIElements                       = "AXLinkedUIElements" //(NSArray *) - corresponding UIElements

  // Text-specific attributes
  case SelectedText                           = "AXSelectedText" //(NSString *) - selected text
  case SelectedTextRange                      = "AXSelectedTextRange" //(NSValue *)  - (rangeValue) range of selected text
  case NumberOfCharacters                     = "AXNumberOfCharacters" //(NSNumber *) - number of characters
  case VisibleCharacterRange                  = "AXVisibleCharacterRange" //(NSValue *)  - (rangeValue) range of visible text
  case SharedTextUIElements                   = "AXSharedTextUIElements" //(NSArray *)  - text views sharing text
  case SharedCharacterRange                   = "AXSharedCharacterRange" //(NSValue *)  - (rangeValue) part of shared text in this view
  case InsertionPointLineNumber               = "AXInsertionPointLineNumber" //(NSNumber *) - line# containing caret
  case SelectedTextRanges                     = "AXSelectedTextRanges" //(NSArray<NSValue *> *) - array of NSValue (rangeValue) ranges of selected text
  /// - note: private/undocumented attribute
  case TextInputMarkedRange                   = "AXTextInputMarkedRange"

  // Parameterized text-specific attributes
  case LineForIndexParameterized              = "AXLineForIndexParameterized" //(NSNumber *) - line# for char index; param:(NSNumber *)
  case RangeForLineParameterized              = "AXRangeForLineParameterized" //(NSValue *)  - (rangeValue) range of line; param:(NSNumber *)
  case StringForRangeParameterized            = "AXStringForRangeParameterized" //(NSString *) - substring; param:(NSValue * - rangeValue)
  case RangeForPositionParameterized          = "AXRangeForPositionParameterized" //(NSValue *)  - (rangeValue) composed char range; param:(NSValue * - pointValue)
  case RangeForIndexParameterized             = "AXRangeForIndexParameterized" //(NSValue *)  - (rangeValue) composed char range; param:(NSNumber *)
  case BoundsForRangeParameterized            = "AXBoundsForRangeParameterized" //(NSValue *)  - (rectValue) bounds of text; param:(NSValue * - rangeValue)
  case RTFForRangeParameterized               = "AXRTFForRangeParameterized" //(NSData *)   - rtf for text; param:(NSValue * - rangeValue)
  case StyleRangeForIndexParameterized        = "AXStyleRangeForIndexParameterized" //(NSValue *)  - (rangeValue) extent of style run; param:(NSNumber *)
  case AttributedStringForRangeParameterized  = "AXAttributedStringForRangeParameterized" //(NSAttributedString *) - does _not_ use attributes from Appkit/AttributedString.h

  // Text attributed string attributes and constants
  case FontText                               = "AXFontText" //(NSDictionary *)  - NSAccessibilityFontXXXKey's
  case ForegroundColorText                    = "AXForegroundColorText" //CGColorRef
  case BackgroundColorText                    = "AXBackgroundColorText" //CGColorRef
  case UnderlineColorText                     = "AXUnderlineColorText" //CGColorRef
  case StrikethroughColorText                 = "AXStrikethroughColorText" //CGColorRef
  case UnderlineText                          = "AXUnderlineText" //(NSNumber *)     - underline style
  case SuperscriptText                        = "AXSuperscriptText" //(NSNumber *)     - superscript>0, subscript<0
  case StrikethroughText                      = "AXStrikethroughText" //(NSNumber *)     - (boolValue)
  case ShadowText                             = "AXShadowText" //(NSNumber *)     - (boolValue)
  case AttachmentText                         = "AXAttachmentText" //id - corresponding element
  case LinkText                               = "AXLinkText" //id - corresponding element
  case AutocorrectedText                      = "AXAutocorrectedText" //(NSNumber *)     - (boolValue)

  // Textual list attributes and constants. Examples: unordered or ordered lists in a document.
  case ListItemPrefixText                     = "AXListItemPrefixText" // NSAttributedString, the prepended string of the list item. If the string is a common unicode character (e.g. a bullet •), return that unicode character. For lists with images before the text, return a reasonable label of the image.
  case ListItemIndexText                      = "AXListItemIndexText" // NSNumber, integerValue of the line index. Each list item increments the index, even for unordered lists. The first item should have index 0.
  case ListItemLevelText                      = "AXListItemLevelText" // NSNumber, integerValue of the indent level. Each sublist increments the level. The first item should have level 0.

  // MisspelledText attributes
  case MisspelledText                         = "AXMisspelledText" //(NSNumber *)     - (boolValue)
  case MarkedMisspelledText                   = "AXMarkedMisspelledText" //(NSNumber *) - (boolValue)

  // Window-specific attributes
  case Main                                   = "AXMain" //(NSNumber *) - (boolValue) is it the main window?
  case Minimized                              = "AXMinimized" //(NSNumber *) - (boolValue) is window minimized?
  case CloseButton                            = "AXCloseButton" //(id) - UIElement for close box (or nil)
  case ZoomButton                             = "AXZoomButton" //(id) - UIElement for zoom box (or nil)
  case MinimizeButton                         = "AXMinimizeButton" //(id) - UIElement for miniaturize box (or nil)
  case ToolbarButton                          = "AXToolbarButton" //(id) - UIElement for toolbar box (or nil)
  case Proxy                                  = "AXProxy" //(id) - UIElement for title's icon (or nil)
  case GrowArea                               = "AXGrowArea" //(id) - UIElement for grow box (or nil)
  case Modal                                  = "AXModal" //(NSNumber *) - (boolValue) is the window modal
  case DefaultButton                          = "AXDefaultButton" //(id) - UIElement for default button
  case CancelButton                           = "AXCancelButton" //(id) - UIElement for cancel button
  case FullScreenButton                       = "AXFullScreenButton" //(id) - UIElement for full screen button (or nil)
  /// - note: private/undocumented attribute
  case FullScreen                             = "AXFullScreen" //(NSNumber *) - (boolValue) is the window fullscreen

  // Application-specific attributes
  case MenuBar                                = "AXMenuBar" //(id)         - UIElement for the menu bar
  case Windows                                = "AXWindows" //(NSArray *)  - UIElements for the windows
  case Frontmost                              = "AXFrontmost" //(NSNumber *) - (boolValue) is the app active?
  case Hidden                                 = "AXHidden" //(NSNumber *) - (boolValue) is the app hidden?
  case MainWindow                             = "AXMainWindow" //(id)         - UIElement for the main window.
  case FocusedWindow                          = "AXFocusedWindow" //(id)         - UIElement for the key window.
  case FocusedUIElement                       = "AXFocusedUIElement" //(id)         - Currently focused UIElement.
  case ExtrasMenuBar                          = "AXExtrasMenuBar" //(id)         - UIElement for the application extras menu bar.
  /// - note: private/undocumented attribute
  case EnhancedUserInterface                  = "AXEnhancedUserInterface" //(NSNumber *) - (boolValue) is the enhanced user interface active?

  case Orientation                            = "AXOrientation" //(NSString *) - NSAccessibilityXXXOrientationValue

  case ColumnTitles                           = "AXColumnTitles" //(NSArray *)  - UIElements for titles

  case SearchButton                           = "AXSearchButton" //(id)         - UIElement for search field search btn
  case SearchMenu                             = "AXSearchMenu" //(id)         - UIElement for search field menu
  case ClearButton                            = "AXClearButton" //(id)         - UIElement for search field clear btn

  // Table/outline view attributes
  case Rows                                   = "AXRows" //(NSArray *)  - UIElements for rows
  case VisibleRows                            = "AXVisibleRows" //(NSArray *)  - UIElements for visible rows
  case SelectedRows                           = "AXSelectedRows" //(NSArray *)  - UIElements for selected rows
  case Columns                                = "AXColumns" //(NSArray *)  - UIElements for columns
  case VisibleColumns                         = "AXVisibleColumns" //(NSArray *)  - UIElements for visible columns
  case SelectedColumns                        = "AXSelectedColumns" //(NSArray *)  - UIElements for selected columns
  case SortDirection                          = "AXSortDirection" //(NSString *) - see sort direction values below

  // Cell-based table attributes
  case SelectedCells                          = "AXSelectedCells" //(NSArray *)  - UIElements for selected cells
  case VisibleCells                           = "AXVisibleCells" //(NSArray *)  - UIElements for visible cells
  case RowHeaderUIElements                    = "AXRowHeaderUIElements" //(NSArray *)  - UIElements for row headers
  case ColumnHeaderUIElements                 = "AXColumnHeaderUIElements" //(NSArray *)  - UIElements for column headers

  // Cell-based table parameterized attributes.  The parameter for this attribute is an NSArray containing two NSNumbers, the first NSNumber specifies the column index, the second NSNumber specifies the row index.
  case CellForColumnAndRowParameterized       = "AXCellForColumnAndRowParameterized" // (id) - UIElement for cell at specified row and column

  // Cell attributes.  The index range contains both the starting index, and the index span in a table.
  case RowIndexRange                          = "AXRowIndexRange" //(NSValue *)  - (rangeValue) location and row span
  case ColumnIndexRange                       = "AXColumnIndexRange" //(NSValue *)  - (rangeValue) location and column span

  // Layout area attributes
  case HorizontalUnits                        = "AXHorizontalUnits" //(NSString *) - see ruler unit values below
  case VerticalUnits                          = "AXVerticalUnits" //(NSString *) - see ruler unit values below
  case HorizontalUnitDescription              = "AXHorizontalUnitDescription" //(NSString *)
  case VerticalUnitDescription                = "AXVerticalUnitDescription" //(NSString *)

  // Layout area parameterized attributes
  case LayoutPointForScreenPointParameterized = "AXLayoutPointForScreenPointParameterized" //(NSValue *)  - (pointValue); param:(NSValue * - pointValue)
  case LayoutSizeForScreenSizeParameterized   = "AXLayoutSizeForScreenSizeParameterized" //(NSValue *)  - (sizeValue); param:(NSValue * - sizeValue)
  case ScreenPointForLayoutPointParameterized = "AXScreenPointForLayoutPointParameterized" //(NSValue *)  - (pointValue); param:(NSValue * - pointValue)
  case ScreenSizeForLayoutSizeParameterized   = "AXScreenSizeForLayoutSizeParameterized" //(NSValue *)  - (sizeValue); param:(NSValue * - sizeValue)

  // Layout item attributes
  case Handles                                = "AXHandles" //(NSArray *)  - UIElements for handles

  // Outline attributes
  case Disclosing                             = "AXDisclosing" //(NSNumber *) - (boolValue) is disclosing rows?
  case DisclosedRows                          = "AXDisclosedRows" //(NSArray *)  - UIElements for disclosed rows
  case DisclosedByRow                         = "AXDisclosedByRow" //(id)         - UIElement for disclosing row
  case DisclosureLevel                        = "AXDisclosureLevel" //(NSNumber *) - indentation level

  // Slider attributes
  case AllowedValues                          = "AXAllowedValues" //(NSArray<NSNumber *> *) - array of allowed values
  case LabelUIElements                        = "AXLabelUIElements" //(NSArray *) - array of label UIElements
  case LabelValue                             = "AXLabelValue" //(NSNumber *) - value of a label UIElement

  // Matte attributes
  // Attributes no longer supported
  case MatteHole                              = "AXMatteHole" //(NSValue *) - (rect value) bounds of matte hole in screen coords
  case MatteContentUIElement                  = "AXMatteContentUIElement" //(id) - UIElement clipped by the matte

  // Ruler view attributes
  case MarkerUIElements                       = "AXMarkerUIElements" //(NSArray *)
  case MarkerValues                           = "AXMarkerValues" //
  case MarkerGroupUIElement                   = "AXMarkerGroupUIElement" //(id)
  case Units                                  = "AXUnits" //(NSString *) - see ruler unit values below
  case UnitDescription                        = "AXUnitDescription" //(NSString *)
  case MarkerType                             = "AXMarkerType" //(NSString *) - see ruler marker type values below
  case MarkerTypeDescription                  = "AXMarkerTypeDescription" //(NSString *)

  // UI element identification attributes
  case Identifier                             = "AXIdentifier" //(NSString *)
}

/// All actions a `UIElement` can support.
/// - seeAlso: [Actions](https://developer.apple.com/library/mac/documentation/Cocoa/Reference/ApplicationKit/Protocols/NSAccessibility_Protocol/#//apple_ref/doc/constant_group/Actions)
public enum Action: String {
  case Press           = "AXPress"
  case Increment       = "AXIncrement"
  case Decrement       = "AXDecrement"
  case Confirm         = "AXConfirm"
  case Pick            = "AXPick"
  case Cancel          = "AXCancel"
  case Raise           = "AXRaise"
  case ShowMenu        = "AXShowMenu"
  case Delete          = "AXDelete"
  case ShowAlternateUI = "AXShowAlternateUI"
  case ShowDefaultUI   = "AXShowDefaultUI"
}
