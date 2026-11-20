import '../models/mission_model.dart';

/// Hardware Item Model for Identification Missions
class HardwareItem {
  final String id;
  final String name;
  final String imagePath;

  HardwareItem({required this.id, required this.name, required this.imagePath});
}

/// Mission Content Data
/// Contains questions, components, steps, and scenarios for all missions
class MissionContentData {
  static const notificationsTitle = 'Notifications';
  static const notificationsAll = 'All';
  static const notificationsUnread = 'Unread';
  static const notificationsMarkAll = 'Mark all read';
  static const notificationsMarkRead = 'Mark as read';
  static const notificationsRead = 'Read';
  static const notificationsEmpty = 'No notifications';
  static const notificationsEmptyHelp =
      'New activity updates will appear here.';
  static const notificationsUnreadEmpty = 'All caught up';
  static const notificationsRefresh = 'Refresh notifications';
  static const notificationsRetry = 'Try again';
  static const notificationsFailed =
      'Notifications could not be loaded. Try again.';
  static const notificationsSaveFailed =
      'Read status could not be saved. Try again.';
  static const notificationsMore = 'Load more';
  static const notificationsOpen = 'Open activity';
  static const notificationsUpdate = 'Update';
  static const activityNoAccess =
      'This activity is no longer available to your account. Refresh your activities or contact your instructor.';
  static const activityOpenFailed =
      'The activity could not be opened. Check your connection and try again.';
  static const homeGreeting = 'Hello';
  static const homeSubtitle = 'Your learning, in one place';
  static const homeLearner = 'Learner';
  static const homeLoading = 'Loading learner dashboard';
  static const homeFailed =
      'Your technical learning record could not be loaded. Refresh to try again.';
  static const homeAttention = 'Needs Your Attention';
  static const homeAttentionEmpty = 'You have no outstanding activities.';
  static const homeToDo = 'To Do';
  static const homeAll = 'All Activities';
  static const homeQuizzes = 'Quizzes';
  static const homeHomework = 'Homework';
  static const homeTechnical = 'Technical';
  static const homeCompleted = 'Completed';
  static const homeOpen = 'Open';
  static const homeClosed = 'Closed';
  static const homeUpcoming = 'Not yet open';
  static const homeTechnicalOpen = 'View activity';
  static const homeViewGrading = 'View Grading';
  static const homeInReview = 'Awaiting instructor review';
  static const homeReleased = 'Released results';
  static const homeAssessment = 'Official assessment';
  static const homePractice = 'Practice';
  static const homeStarted = 'In progress';
  static const homeAssigned = 'Assigned';
  static const homeNoMatch = 'No activities in this view.';
  static const homeViewAll = 'View all activities';
  static const homeActivityView = 'Activity view';
  static String homeSummary(int quizzes, int homework, int technical) =>
      '$quizzes quizzes · $homework homework · $technical technical';
  static String notificationBell(int unread) => 'Notifications, $unread unread';
  static const assignedQuizzes = 'Assigned Quizzes';
  static const technicalActivities = 'Technical activities';
  static const technicalAssigned = 'Technical tasks';
  static const technicalNext = 'Your next technical activity will appear here';
  static const technicalEmpty = 'No technical activities assigned.';
  static const homeworkAssignments = 'Homework Assignments';
  static const classActivitiesLoading = 'Loading class activities';
  static const classActivitiesUnavailable =
      'Class activities could not be loaded.';
  static const classActivitiesRetry = 'Refresh activities';
  static const homeworkEmpty = 'No homework assigned';
  static const quizzesEmpty = 'No quizzes assigned';
  static const homeworkView = 'View Assignment';
  static const homeworkTitle = 'Assignment';
  static const homeworkInstructions = 'Instructions';
  static const homeworkFiles = 'Instructor attachments';
  static const homeworkAnswer = 'Written answer';
  static const homeworkAnswerHint =
      'Enter your completed answer, attach files, or both.';
  static const homeworkAnswerFiles = 'Your completed files';
  static const homeworkAddFile = 'Attach completed file';
  static const homeworkFileHelp =
      'PDF, JPG, PNG, WebP, or TXT. Up to 10 MB per file; 5 files.';
  static const homeworkReview = 'Review submission';
  static const homeworkReviewTitle = 'Review your homework';
  static const homeworkReviewHelp =
      'Check your answer and files. You can submit once. Your Instructor will review your work.';
  static const homeworkSubmit = 'Submit Assignment';
  static const homeworkAssigned = 'Assigned';
  static const homeworkSubmitted = 'Submitted for Grading';
  static const homeworkGraded = 'Graded';
  static const homeworkLateAllowed =
      'Deadline Passed — Late Submission Allowed';
  static const homeworkFeedback = 'Instructor feedback';
  static const homeworkNoDeadline = 'No deadline';
  static const homeworkNoAnswer = 'File submission';
  static const homeworkOutside =
      'Complete the homework outside ByteQuest, then return to submit your answer or files.';
  static const homeworkFailed =
      'Homework could not be saved. Refresh to check its status, then retry.';
  static const homeworkFileFailed =
      'File could not be uploaded. Check the file and retry.';
  static const homeworkOpenFailed = 'File could not be opened. Try again.';
  static const homeworkTooLarge = 'Choose a nonempty file up to 10 MB.';
  static const homeworkFileLimit = 'You can attach up to 5 files.';
  static const homeworkRequired = 'Enter an answer or attach a completed file.';
  static const homeworkRemoveFile = 'Remove file from submission';
  static const homeworkRefresh = 'Refresh assignment';
  static const homeworkClose = 'Close assignment';
  static const homeworkSubmitting = 'Saving submission…';
  static const homeworkUploading = 'Uploading file…';
  static const recoveryEmailSent =
      'If an account exists, recovery instructions have been sent. Open the link in your browser, choose a new password, then return to ByteQuest to sign in.';
  static const recoveryEmailUnavailable =
      'Recovery email could not be sent. Check your connection and try again, or contact the administrator.';
  static const homeworkCancel = 'Keep editing';
  static const quizClosedDeadline = 'Quiz Closed — Deadline Passed';
  static const quizStart = 'Start quiz';
  static const quizContinue = 'Continue quiz';
  static const quizViewResult = 'View Result';
  static const quizClosed = 'Closed';
  static const quizExpiryHelp =
      'Saved answers are preserved. Ask your Instructor to reopen this quiz to resume the same attempt.';
  static const quizOneAttempt = 'One attempt per quiz';
  static String homeworkLateBy(String duration) => 'Late by $duration';
  static String homeworkDue(String date) => 'Deadline: $date';
  static String homeworkSubmittedAt(String date) => 'Submitted: $date';
  static String homeworkEffectiveDeadline(String date) =>
      'Deadline at submission: $date';
  static String homeworkScore(num score) => 'Score: $score/100';
  static const quizAttemptAvailable = 'Not started — 1 attempt available';
  static const quizAttemptInProgress = 'In progress — Continue attempt';
  static const quizAttemptUsed = 'Submitted — Attempt used';
  static const quizAttemptUnavailable = 'Unavailable — Quiz not accessible';
  static const loadingLabel = 'Working…';
  static const backLabel = 'Back';
  static const settingsLabel = 'Settings';
  static const learningPathLabel = 'Learning path';
  static const quizzesLabel = 'Quizzes';
  static const controlsLabel = 'Task controls';
  static const workspaceLabel = 'Technical workspace';
  static const workspaceGuideLabel = 'Mission guide';
  static const workspaceExpandControls = 'Expand task controls';
  static const workspaceExpandScene = 'Expand workspace';
  static const workspaceCloseGuide = 'Close guide';
  static const workspaceFeedbackLabel = 'Action feedback';
  static const workspaceViewFeedback = 'Read action feedback';
  static const workspaceZoomIn = 'Zoom in workspace';
  static const workspaceZoomOut = 'Zoom out workspace';
  static const workspaceFitView = 'Fit and reset workspace view';
  static const taskStatusLabel = 'Remaining actions';
  static const inspectionsTaskLabel = 'Inspections';
  static const identificationTapHint =
      'Tap one component for this role. The readiness test checks your choice.';
  static const placementsTaskLabel = 'Placements';
  static const connectionsTaskLabel = 'Connections';
  static const configurationTaskLabel = 'Configuration fields';
  static const learnLabel = 'Learn';
  static const fullNameFieldLabel = 'Full name (required)';
  static const emailFieldLabel = 'Email address (required)';
  static const passwordFieldLabel = 'Password (required)';
  static const confirmPasswordFieldLabel = 'Confirm password (required)';
  static const signupNetworkUnavailableMessage =
      'Cannot reach the account server. Check this device\'s internet connection and try again.';
  static const signupAlreadyRegisteredMessage =
      'This email is already registered. Please log in instead.';
  static const signupInvalidEmailMessage =
      'Please check the email address and try again.';
  static const signupWeakPasswordMessage =
      'Password is too weak. Please use a stronger password.';
  static const signupProvisioningMessage =
      'Your account needs setup by an administrator. Please contact support.';
  static const signupDisabledMessage =
      'New account registration is unavailable. Please contact support.';
  static const signupEmailDeliveryMessage =
      'Could not send the confirmation email. Please try again later.';
  static const signupUnexpectedMessage =
      'Could not create your account. Please try again.';

  static String signupFailureMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('failed host lookup') ||
        message.contains('socketexception') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('connection reset') ||
        message.contains('connection timed out')) {
      return signupNetworkUnavailableMessage;
    }
    if (message.contains('user already registered') ||
        message.contains('email already exists') ||
        message.contains('already registered')) {
      return signupAlreadyRegisteredMessage;
    }
    if (message.contains('invalid email') ||
        message.contains('email_address_invalid')) {
      return signupInvalidEmailMessage;
    }
    if (message.contains('password') &&
        (message.contains('weak') || message.contains('at least'))) {
      return signupWeakPasswordMessage;
    }
    if (message.contains('provisioning is incomplete')) {
      return signupProvisioningMessage;
    }
    if (message.contains('signup_disabled') ||
        message.contains('signups not allowed')) {
      return signupDisabledMessage;
    }
    if (message.contains('error sending confirmation email') ||
        message.contains('email rate limit')) {
      return signupEmailDeliveryMessage;
    }
    return signupUnexpectedMessage;
  }

  static const newPasswordFieldLabel = 'New password (required)';
  static const studentIdFieldLabel = 'Student ID (optional)';
  static const sectionFieldLabel = 'Section or set (optional)';
  static const goalFieldLabel = 'Learning goal (optional)';
  static const profileAvatarLabel = 'Profile avatar';
  static const phaseCompleteLabel = 'Actions complete';
  static const controlsScrollHint = 'Scroll here for all task controls';
  static const guidanceHeading = 'How to complete this task';
  static const guideNextHeading = 'What to do next';
  static const guideShowMeHow = 'Show me where';
  static const tutorialReplay = 'Replay tutorial';
  static const tutorialStart = 'Start tutorial';
  static const tutorialSkip = 'Skip';
  static const tutorialNext = 'Next';
  static const tutorialFinish = 'Finish';
  static const tutorialHeading = 'Quick mission tour';
  static const tutorialInvite =
      'New to missions? Take a quick tour of the controls.';
  static const tutorialWorkspace =
      'The technical workspace is the large area with equipment. Tap a device to inspect it. Use Objects if a device is hard to see.';
  static const tutorialInstructions =
      'What to do next names the current task. Open its steps to see what is done and what remains.';
  static const tutorialEquipment =
      'Place equipment and Connect ports are workspace tabs. Open the tab named in the guide before choosing a part or port.';
  static const tutorialIdentification =
      'For identification, tap an item in Selection set. If Confirm selection appears, tap it after choosing.';
  static const tutorialPlacement =
      'For placement, tap a part and then a compatible slot, or drag the part onto the slot. Choose an orientation if asked.';
  static const tutorialProgress =
      'The progress count shows recorded required actions. Rejected actions do not increase it.';
  static const tutorialContinue =
      'Continue or Review evidence is at the bottom. Its message explains what still needs work.';
  static const tutorialTimer =
      'The COC practice timer continues during this tour.';
  static const guideHideHighlight = 'Hide highlight';
  static const guideDone = 'Done';
  static const guideCurrent = 'Now';
  static const guideWaitingForSync =
      'Action saved on this device. Server evidence is still waiting to sync.';
  static const guideReadyToContinue =
      'All required actions completed. Tap Continue.';
  static String guideActionCount(int completed, int total) =>
      '$completed of $total actions completed · ${total - completed} remaining';
  static String guideRemaining(int remaining) =>
      '$remaining required ${remaining == 1 ? 'action remains' : 'actions remain'} before Continue.';
  static String guideInspectItem(String label) =>
      'Tap Objects in the workspace or scroll to Inspection targets below. Select $label and read its condition. No dragging is needed.';
  static const guideSelect =
      'Below the workspace, tap items in Selection set, then tap Confirm selection.';
  static const guideIdentify =
      'Below the workspace, tap one component in Selection set. Your tap records it; no dragging is needed.';
  static String guideClassify(String label) =>
      'Scroll below the workspace to $label. Tap the component that fits this role.';
  static const guideTool =
      'Below the workspace, tap an equipment target under Target, then tap a tool in the tool tray. Check the feedback.';
  static String guideToolTarget(String label) =>
      'Below the workspace, tap $label under Target, then choose a tool in the tool tray. Check the feedback.';
  static String guideConnect(String label, bool workspaceMode) => workspaceMode
      ? 'Tap Connect ports above the workspace, then tap $label and a compatible destination. You can also drag the source onto a port.'
      : 'Below the workspace, tap $label under Sources, then tap a compatible port under Destinations. You can also drag the source onto a port.';
  static const guideConnectPorts =
      'Scroll to Sources and Destinations below the workspace. Tap a source, then a compatible port.';
  static String guideConfigure(List<String> fields) =>
      'Scroll to Configuration values. Set ${fields.isEmpty ? 'the required fields' : fields.join(', ')}, then tap Apply configuration.';
  static const guideSequence =
      'Scroll to the procedure list. Use the up or down arrows or drag handle to order the steps, then tap Apply procedure order.';
  static const guideTapSequence =
      'Scroll to the procedure list. Use the up or down arrows to order the steps, then tap Apply procedure order.';
  static String guideMatch(String label) =>
      'Under Sources below the workspace, tap $label, then tap its matching destination under Matches.';
  static String guidePlace(String label, bool workspaceMode) => workspaceMode
      ? 'Tap Place equipment above the workspace, then select $label and a compatible destination, or drag it onto a slot. You can also use Components and devices below: choose an orientation if shown, then tap Install selected component.'
      : 'Below the workspace, tap $label under Components and devices, choose a compatible destination and orientation if shown, then tap Install selected component.';
  static const guideDiagnostic =
      'Scroll to Troubleshooting diagnostics. Tap a diagnostic action to reveal one finding, then read Recorded findings.';
  static String guideDiagnosticFinding(int number) =>
      'In Troubleshooting diagnostics, run a diagnostic action to reveal finding $number. Read Recorded findings before deciding.';
  // Layout-neutral: Run test is below the workspace in portrait and in the
  // side panel in landscape.
  static const guideTest =
      'Tap Run test, wait for Test completed and read the measurements.';
  static const guideTestInterpret =
      'Below the test result, enter an interpretation and tap Record test interpretation.';
  static const guideObserve =
      'Scroll to the observation field. Enter what you can see, then tap Record observation.';
  static const guideDecide =
      'Scroll to the decision buttons. Read the evidence, then tap the action it supports.';
  static const guideInterpret =
      'Scroll to the result field. Explain the result, then tap Record interpretation.';
  static const guideReview =
      'Review the recorded actions below. If evidence is pending, tap Retry pending evidence. When ready, tap Confirm evidence at the bottom.';
  static const guideReviewPending =
      'Scroll to Evidence review and tap Retry pending evidence. Wait for the action to sync before confirming.';
  static const guideReviewIncomplete =
      'Scroll to Evidence review and tap Return to mission. Complete the missing task, then review again.';
  static String guideBlocked(int completed, int total, String next) =>
      'Cannot continue yet: $completed of $total required actions complete. $next';
  static String guideRejected(int completed, int total, String next) =>
      'That action did not count. $completed of $total required '
      'actions complete. $next';
  static String guideReviewSyncStatus(int pending, int failed) =>
      'Cannot confirm yet: $pending evidence ${pending == 1 ? 'action' : 'actions'} waiting to sync, $failed needing retry. Scroll to Evidence review and tap Retry pending evidence.';
  static String guideOperation(String label) =>
      'Scroll to Operate the equipment and tap $label. Check the equipment feedback.';
  static const guideOperationDecision =
      'Scroll to Operate the equipment. Use the case findings to choose a correction button, then check the feedback.';
  static const guideCheckRequirements =
      'Check the remaining-task status below and complete the indicated equipment check.';
  static const guidanceShowSteps = 'Show steps';
  static const guidanceHideSteps = 'Hide steps';
  static const guidanceObjectiveLabel = 'Objective';
  static const guidanceProgressLabel = 'Required-action progress';
  static const guidanceHintLabel = 'Hint';
  static const guidanceActionRecorded = 'Main action recorded';
  static const guidanceActionPending = 'Main action still needed';
  static const diagnosticFindingsProgressLabel = 'Diagnostic findings';
  static const rolesIdentifiedProgressLabel = 'Roles identified';
  static const workOrderChecksProgressLabel = 'Work-order checks';
  static const guidanceIdentifyLabel = 'Tap to Identify';
  static const guidanceInspectLabel = 'Tap to Inspect';
  static const guidanceInspectPlaceLabel = 'Inspect and Place';
  static const guidanceSelectLabel = 'Select';
  static const guidanceToolLabel = 'Use Tool';
  static const guidanceConnectLabel = 'Connect';
  static const guidanceConfigureLabel = 'Configure';
  static const guidanceSequenceLabel = 'Order Steps';
  static const guidanceMatchLabel = 'Match';
  static const guidancePlaceLabel = 'Drag & Drop';
  static const guidanceTapPlaceLabel = 'Tap to Place';
  static const guidanceTroubleshootLabel = 'Troubleshoot';
  static const guidanceTestLabel = 'Test';
  static const guidanceObserveLabel = 'Observe';
  static const guidanceDecideLabel = 'Decide';
  static const guidanceInterpretLabel = 'Interpret';
  static const guidanceReviewLabel = 'Review';
  static const guidanceInspectSevenSummary =
      'Tap all seven components and read their inspection details.';
  static const guidanceIdentifyRoleSummary =
      'Tap one component for each requested role.';
  static const guidanceInspectSummary =
      'Tap each required object to inspect its condition.';
  static const guidanceInspectPlaceSummary =
      'Place required equipment, then complete the phase controls.';
  static const guidanceSelectSummary =
      'Choose the items supported by the work order.';
  static const guidanceToolSummary =
      'Choose a tool and apply it to a compatible target.';
  static const guidanceConnectSummary =
      'Connect each required source to its destination.';
  static const guidanceConfigureSummary =
      'Enter the required values and apply configuration.';
  static const guidanceSequenceSummary =
      'Arrange the procedure and apply its order.';
  static const guidanceMatchSummary =
      'Pair each source with the matching destination.';
  static const guidancePlaceSummary =
      'Install each component in a compatible slot.';
  static const guidanceTroubleshootSummary =
      'Run diagnostics and use the revealed findings.';
  static const guidanceTestSummary =
      'Run the test and inspect its measured output.';
  static const guidanceObserveSummary =
      'Record the condition that is actually visible.';
  static const guidanceDecideSummary =
      'Choose the next action supported by the evidence.';
  static const guidanceInterpretSummary =
      'Explain what the recorded result indicates.';
  static const guidanceReviewSummary =
      'Review saved work before confirming evidence.';
  static const guidanceSupplementalPlacement =
      'Open Place equipment in the workspace. Select a component and install it in a compatible destination.';
  static const guidanceSupplementalConnection =
      'Open Connect ports and link the required source and destination interfaces.';
  static const guidanceSupplementalConfiguration =
      'Complete the configuration controls below, then tap Apply configuration.';
  static const guidanceSupplementalTool =
      'Select the preparation tool and the equipment target shown below.';
  static const guidanceRoleSelection =
      'For each requested role, tap the component you choose. Your selection is recorded when tapped.';
  static const guidanceRoleSelectionFinish =
      'Check that every requested role has a selected component before continuing.';
  static const guidanceInspectObjects =
      'Tap each listed component or inspection target in the workspace or task controls.';
  static const guidanceReadInspection =
      'Read the condition and function information shown after each tap.';
  static const guidanceInspectFinish =
      'Inspect every required target, then check the remaining-action status.';
  static const guidanceChooseItems =
      'Read the work order and tap the items you believe are needed.';
  static const guidanceConfirmSelection =
      'Tap Confirm selection to record your choices.';
  static const guidanceChooseTool =
      'Select a tool from the available tool controls.';
  static const guidanceApplyTool =
      'Choose the equipment target and check the tool-contact feedback.';
  static const guidanceChooseConnectionSource =
      'Select a source port or cable endpoint in Connect ports.';
  static const guidanceChooseConnectionDestination =
      'Tap the matching destination, or drag the source to it in the workspace.';
  static const guidanceCheckConnection =
      'Check the recorded link and connect any remaining required sources.';
  static const guidanceOpenConfiguration =
      'Open the configuration controls below the workspace.';
  static const guidanceEnterConfiguration =
      'Enter or choose each value required by the work order.';
  static const guidanceApplyConfiguration =
      'Tap Apply configuration and correct any field the validation rejects.';
  static const guidanceReadSequence =
      'Read the technical procedure and its listed actions.';
  static const guidanceArrangeSequence =
      'Move actions with the arrows or drag handle into the required order.';
  static const guidanceApplySequence =
      'Tap Apply procedure order to record the sequence.';
  static const guidanceChooseMatchSource =
      'Choose a source item from the matching controls.';
  static const guidanceChooseMatchDestination =
      'Choose the destination that fits that source.';
  static const guidanceMatchFinish =
      'Record all required pairs and check for unmatched sources.';
  static const guidanceChooseComponent =
      'Select the component you want to install from Components and devices.';
  static const guidanceDragComponent =
      'Drag it toward a compatible slot; release when the destination is highlighted.';
  static const guidanceConfirmPlacement =
      'For tap placement, choose the destination and orientation, then tap Install selected component.';
  static const guidancePlaceFinish =
      'Install the remaining required components before continuing.';
  static const guidanceReadSymptom =
      'Read the reported symptom and inspect the visible equipment state.';
  static const guidanceRunDiagnostic =
      'Tap a diagnostic action that can reveal a new measured fact.';
  static const guidanceUseFindings =
      'Read each recorded finding before choosing a correction or retest.';
  static const guidanceRunTest = 'Tap Run test in the task controls.';
  static const guidanceReadTest =
      'Read the displayed measurements and operating status.';
  static const guidanceInterpretTest =
      'Enter your interpretation, then tap Record test interpretation.';
  static const guidanceObserveCondition =
      'Inspect the visible or reported condition described in this phase.';
  static const guidanceRecordObservation =
      'Enter only what you observed, then tap Record observation.';
  static const guidanceReviewEvidence =
      'Review the information gathered in earlier phases.';
  static const guidanceChooseDecision =
      'Tap the action that best fits the current technical evidence.';
  static const guidanceReadResult =
      'Read the recorded test or diagnostic result.';
  static const guidanceRecordInterpretation =
      'Explain what it indicates, then tap Record interpretation.';
  static const guidanceReviewRecordedWork =
      'Review the recorded actions and any measured results.';
  static const guidanceRetryEvidence =
      'If evidence is pending, use Retry pending evidence before confirming.';
  static const guidanceConfirmEvidence =
      'Tap Confirm evidence when the review and required checks are ready.';
  static const guidanceEquipmentOperations =
      'Use the Equipment operations buttons for the work-order checks in this phase.';
  static const guidanceIdentificationHint =
      'Tap a component to inspect or identify it. No dragging is required.';
  static const guidancePlacementHint =
      'If a component does not fit, inspect the slot and choose a compatible destination.';
  static const guidanceConnectionHint =
      'Check connector and signal types before linking two ports.';
  static const guidanceConfigurationHint =
      'Use the work order and field format hints when checking values.';
  static const guidanceDiagnosticHint =
      'Use the displayed measurement before choosing the next action.';
  static const guidanceGeneralHint =
      'Check the remaining-action status to see what is still required.';
  static const readyToContinueLabel =
      'Phase actions complete. Continue when ready.';
  static const phaseActionsPendingLabel =
      'Complete the task controls for this phase.';
  static const technicalEvidenceSyncFailed =
      'Technical evidence could not be synchronized. Retry this action.';
  static const retryActionLabel = 'Retry';
  static const phaseSaveFailed =
      'The phase could not be saved. Retry before continuing.';
  static const reviewSaveFailed =
      'The review state could not be saved. Retry before returning.';
  static const equipmentChecksPendingLabel =
      'Complete the equipment checks below.';
  static const sequencePendingLabel =
      'Arrange the steps and apply the procedure order.';
  static const sequenceRecordedLabel = 'Procedure order recorded.';
  static const sequenceHelp =
      'Move steps with the arrows or drag handle, then tap Apply procedure order.';
  static const sequenceTapHelp =
      'Move steps with the arrows, then tap Apply procedure order.';
  static const placementTapHelp =
      'Tap a component, choose a location and orientation, then install. You can also drag in the workspace.';
  static const connectionTapHelp =
      'Tap a source, then its destination. You can also drag in the workspace.';
  static const sourcesLabel = '1. Select a source';
  static const destinationsLabel = '2. Select a destination';
  static const workspaceSourceAction = 'Drag or tap';
  static const workspaceDestinationAction = 'Drop here';
  static const workspaceInstalledLabel = 'Installed';
  static const workspaceConnectedLabel = 'Connected';
  static const workspaceSelectSourceFirst =
      'Select a part or cable on the left first, then choose a location on the right.';
  static const workspaceSelectDestination =
      'Selected. Tap a destination on the right.';
  static const workspaceAlreadyPlaced =
      'This equipment is already installed. Select an unplaced component.';
  static const workspaceAlreadyConnected =
      'These ports are already connected. Select another endpoint pair.';
  static const reviewEvidenceLabel = 'Review evidence';
  static const confirmEvidenceLabel = 'Confirm evidence';
  static const reviewReadyLabel =
      'Review the recorded work above, then confirm.';
  static const reviewPendingLabel =
      'Evidence is waiting to sync. Use Retry pending evidence in the controls.';
  static const reviewSavedLabel =
      'Saved successfully. Use Back to leave this mission.';
  static const resetProgressTitle = 'Reset this practice run?';
  static const resetProgressMessage =
      'This removes the saved work for this practice run. You will start the mission again.';
  static const discardProgressTitle = 'Discard this practice run?';
  static const discardProgressMessage =
      'Your current placements, connections and phase progress will be removed. This cannot be undone.';
  static const profileLoadFailed =
      'Your profile could not be loaded. Check your connection and try again.';
  static const profileSaveFailed =
      'Your changes could not be saved. Your entries are still here. Check your connection and tap Save Changes again.';
  static const termsLinkLabel = 'Read Terms & Privacy';
  static const termsAgreementLabel =
      'I agree to the Terms of Service and Privacy Policy';
  static const showPasswordLabel = 'Show password';
  static const hidePasswordLabel = 'Hide password';
  static const searchHelpLabel = 'Search help articles';
  static const optionalLearnerIdLabel = 'Learner ID (optional)';
  static const optionalSchoolLabel = 'School (optional)';
  static const optionalSectionLabel = 'Course / Section (optional)';
  static String taskCount(String task, int done, int total) =>
      '$task: $done of $total';
  static String phasePosition(int phase, int total, String title) =>
      'Phase $phase of $total · $title';
  static String moveStep(String label, String direction) =>
      'Move $label $direction';
  static const practiceProgressTitle = 'Virtual practice progression';
  static const practiceTimerStart = 'Start timed COC practice';
  static const practiceTimerResume = 'Continue timed COC practice';
  static const practiceTimerRestart = 'Start a new timed practice session';
  static const practiceTimerNotStarted =
      'Start this COC practice session to use its five mission workspaces.';
  static const practiceTimerProvisional =
      '60 minutes for all five missions. ByteQuest practice default, not an official TESDA limit.';
  static const practiceTimerExpired =
      'Practice time has ended. Your recorded evidence and mission progress are preserved. Start a new practice session from the COC path to continue.';
  static const practiceTimerClockChanged =
      'The device clock moved backward. Practice actions are paused. Restore the correct device time and reopen this COC.';
  static const practiceTimerSaveFailed =
      'The practice timer could not be saved. Try again before starting.';
  static const practiceTimerRemainingLabel = 'COC practice time remaining';
  static const practiceTimerCompactLabel = 'COC practice';
  static const practiceTimerExpiredShort = 'Practice time ended';
  // Threshold warnings: shown while less than [minutes] remain, beside the
  // exact countdown, so they never read as the remaining time.
  static String practiceTimerWarningShort(int minutes) =>
      'Under $minutes min left';
  static String practiceEvidencePreserved(int accepted, int pending) =>
      '$accepted evidence actions saved; $pending waiting to sync.';
  static String practiceTimerWarning(int minutes) => minutes == 1
      ? 'Less than 1 minute remains in this COC practice session.'
      : 'Less than $minutes minutes remain in this COC practice session.';

  /// The warning threshold (1, 5 or 10 minutes) that [remaining] is under,
  /// or null above 10 minutes.
  static int? practiceTimerThreshold(Duration remaining) {
    for (final minutes in const [1, 5, 10]) {
      if (remaining < Duration(minutes: minutes)) return minutes;
    }
    return null;
  }
  static const loadingPracticeProgressLabel = 'Loading practice access';
  static const practiceMissionsPendingLabel =
      'Complete the remaining missions below to unlock the COC quiz.';
  static const practiceQuizReadyLabel =
      'All five missions are verified. Take the COC quiz to finish this COC.';
  static const practiceQuizReviewLabel = 'Review COC quiz';
  static String practiceMissionCount(int count) =>
      '$count of 5 practice missions verified';
  static String practiceCocTitle(String coc) => switch (coc) {
        'coc1' => 'Install and Configure Computer Systems',
        'coc2' => 'Set Up Computer Networks',
        'coc3' => 'Set Up Computer Servers',
        'coc4' => 'Maintain and Repair Computer Systems',
        _ => 'Computer Systems Servicing',
      };
  static String practiceMissionNumber(int number) => 'Mission $number of 5';
  static const practiceMissionVerifiedLabel = 'Verified practice';
  static const practiceMissionAvailableLabel = 'Available for practice';
  static const practiceMissionSelectedLabel = 'Selected mission';
  static const practiceMissionVerifiedShortLabel = 'Verified';
  static const practiceCocCompleteLabel = 'COC complete';
  static const practiceCocLockedLabel = 'Locked';
  static const practiceShowMissionDetails = 'Show mission details';
  static const practiceHideMissionDetails = 'Hide mission details';
  static const practiceProgressUnavailable =
      'Practice access could not be verified. Check your connection and retry.';
  static const practiceLockedMessage =
      'Complete the earlier COCs and pass their practice quizzes to unlock this workspace.';
  // Module methodology: the COC quiz opens once every published lesson and
  // mission of the COC's modules is complete, not after five missions.
  static const practiceSavedMessage =
      'Practice work verified and saved. The COC quiz opens when every lesson and mission in this COC is complete.';
  static const practiceSubmitFailed =
      'The server could not verify this work. Review the measured results and retry; your progress is saved.';
  static const practiceVerifyUnreachable =
      'Could not reach ByteQuest to verify. Your evidence is saved — retry when you are online.';
  static const assessmentSubmitFailed =
      'Evidence could not be submitted. Your mission progress is preserved.';
  static const practiceQuizTitle = 'COC practice quiz';
  static const practiceQuizNotice =
      'Pass with at least 80% to complete this practice COC. This learning score is separate from instructor-released assessment results.';
  static const practiceQuizStart = 'Take or resume COC quiz';
  static const practiceQuizSubmit = 'Submit quiz';
  static const practiceQuizRetry = 'Try again';
  static const practiceQuizFailed =
      'Quiz unavailable. Your saved answers are preserved. Retry when connected.';
  static const practiceQuizFallback = 'Using the TESDA-aligned question bank.';
  static const practiceQuizAi =
      'Questions generated from the TESDA-aligned practice bank.';
  static const practiceQuizPassed = 'Practice quiz passed. COC progress saved.';
  static const practiceQuizNeedsReview =
      'Review the explanations and practice again before retrying.';
  static const placementComponentsLabel = 'Components and devices';
  static const workspaceBuildLabel = 'Place equipment';
  static const workspaceInspectLabel = 'Inspect';
  static const workspaceConnectLabel = 'Connect ports';
  static const workspaceSavingLabel = 'Saving action…';
  static const workspaceBuildHint =
      'Drag equipment to a work location. You can also select equipment, then tap its destination.';
  static const workspaceConnectHint =
      'Drag from a source port to a destination. You can also tap the two endpoints.';
  static const workspaceInspectHint =
      'Inspect equipment, configure it, and run the work-order checks.';
  static const workspacePreparationHint =
      'Place the equipment in the workspace, then complete the inspection and work-order checks.';
  static const workspaceOrientationTitle = 'Align the component';
  static const workspaceOrientationHint =
      'Choose the physical orientation before seating this component.';
  static const workspaceObjectsLabel = 'Objects';
  static String workspaceDragLabel(String label) =>
      'Drag $label to a work location';
  static String workspaceDropLabel(String label) =>
      'Place selected equipment at $label';
  static const placementDestinationsLabel = 'Installation locations';
  static const placementOrientationLabel = 'Orientation';
  static const placementConfirmLabel = 'Install selected component';
  static const equipmentStateLabel = 'Equipment state';
  static const equipmentOperationsLabel = 'Operate the equipment';
  static const equipmentOutputLabel = 'Measured simulation output';
  static const equipmentReadyLabel = 'Operating';
  static const equipmentAttentionLabel = 'Attention required';
  static const equipmentRecordedFeedback = 'Equipment action recorded.';
  static const equipmentUpdatedFeedback =
      'Equipment state updated. Run a fresh test to verify the change.';
  static const incompatibleConnectionFeedback =
      'These interfaces cannot establish the requested link. Inspect their connector and signal types.';
  static const incompatiblePlacementFeedback =
      'The component interface does not fit this destination. Inspect the socket or slot specification.';
  static const incorrectPlacementTitle = 'Component does not fit here';
  static const incorrectPlacementCloseLabel = 'Close';
  static String incorrectPlacementMessage(
      String reason, String? component, String? destination) {
    if (component == null || destination == null) return reason;
    return '$component to $destination\n\n$reason';
  }

  static const orientationFeedback =
      'The keyed connector is not aligned. Inspect the notch before seating the component.';

  // Assembly bench (COC1 M2): practice feedback names the physical reason.
  static const Map<String, String> benchOrientationFeedback = {
    'cpu':
        'The processor only drops into the socket one way: rotate it until its gold triangle sits on the triangle printed on the socket.',
    'ram_1':
        'The module notch does not meet the slot key. Rotate the module so the notch lines up with the key, then press it in.',
    'ram_2':
        'The module notch does not meet the slot key. Rotate the module so the notch lines up with the key, then press it in.',
    'psu':
        'The power supply does not sit flat in the bay this way. Turn it so its fan faces the intake vent in the bay floor.',
  };
  static const Map<String, String> benchRequirementFeedback = {
    'cpu':
        'The socket load plate is closed. Open the load lever before seating the processor.',
    'cooler':
        'The cooler mounts over the processor. Seat the processor in the socket first.',
    'ram_1':
        'The DIMM latches are closed. Open them before inserting a module.',
    'ram_2':
        'The DIMM latches are closed. Open them before inserting a module.',
    'io_shield':
        'The I/O shield snaps in from inside the case and cannot pass the installed motherboard. Remove the motherboard, fit the shield, then reinstall the board.',
  };
  static const benchRemovalFeedback =
      'Part removed. Reseat it correctly, then run the test again.';
  static const benchRemovalUnavailable =
      'That part is not installed, so there is nothing to remove.';

  // Assembly bench chrome.
  static String benchStepPosition(int step, int total, String label) =>
      'Step $step of $total · $label';
  static String benchStepsDone(int total) =>
      'All $total steps done · continue when ready';
  static const benchAssessmentHeader = 'Assessment · work without hints';
  static String benchElapsedSemantics(String time) => 'Elapsed time $time';
  static String benchCountsSemantics(
          int valid, int invalid, int corrections, int faults) =>
      '$valid actions accepted, $invalid refused, $corrections corrections, '
      '$faults power-on faults';
  static const benchMatView = 'Anti-static mat';
  static const benchBoardView = 'Motherboard close-up';
  static const benchChassisView = 'Open case';
  static const benchShowBoard = 'Show the motherboard close-up';
  static const benchShowCase = 'Show the whole case';
  static const benchPartsHint =
      'Drag a part onto the bench, or tap it and then tap where it goes.';
  static const benchCablesHint =
      'Drag a connector onto its header, or tap the cable and then the header.';
  static const benchInspectHint =
      'Tap each part on the mat to inspect it, then prepare ESD protection.';
  static String benchPartSelected(String part) =>
      '$part selected — tap where it goes, or rotate it first.';
  static String benchCableSelected(String cable) =>
      '$cable selected — tap the header it plugs into.';
  static String benchInstalledSelected(String part) =>
      '$part is installed. Remove it to reseat it.';
  static const benchRotateLabel = 'Rotate';
  static String benchRotateSemantics(String part, String degrees) =>
      'Rotate $part by 90 degrees. Now turned $degrees degrees.';
  static const benchRemoveLabel = 'Remove';
  static String benchRemoveSemantics(String part) =>
      'Remove $part from where it is installed';
  static const benchCancelLabel = 'Cancel';
  static String benchPartSemantics(String part, bool installed) => installed
      ? '$part, installed. Double tap to select it.'
      : '$part. Drag it to the bench, or double tap to select it.';
  static String benchCableSemantics(String cable, String? header) =>
      header == null
          ? '$cable, not connected. Double tap to select it.'
          : '$cable, connected to $header. Double tap to select it.';
  static String benchSlotSemantics(String slot, String? part) => part == null
      ? '$slot, empty. Double tap to install the selected part here.'
      : '$slot, holds $part.';
  static String benchHeaderSemantics(String header) =>
      '$header. Double tap to connect the selected cable here.';
  static String benchInspectSemantics(String part, bool inspected) =>
      inspected ? '$part, inspected' : '$part. Double tap to inspect.';
  static String benchOperationSemantics(String label, bool enabled) =>
      enabled ? label : '$label — not available yet';
  static String benchInstallChip(String slot) => slot;
  static const benchInspectionTitle = 'Inspection';
  static const benchReadMore = 'Read the full note';
  static const benchDismissInformation = 'Hide this note';
  static const benchDropOnTarget =
      'Release the part over a slot, bay or header on the bench.';
  // Neutral in both modes: it names the equipment, never the next step.
  static String benchOperationNotYet(String label) =>
      '$label is not possible yet. Finish the work it depends on first.';

  // Physical holds on the bench. Nothing is recorded for a held part or
  // lever; practice names what holds it, assessment only that it is held.
  static const benchHeldByLatches =
      'The DIMM latches hold the module in its slot. Open the latches to release it, then lift it out.';
  static const benchHeldByLoadPlate =
      'The socket load plate holds the processor down. Open the load lever before lifting the processor out.';
  static const benchHeldByCooler =
      'The cooler sits on top of the processor. Take the cooler off before lifting the processor out.';
  static const benchHeldByMotherboard =
      'The installed motherboard covers the I/O shield. Remove the motherboard before taking the shield out.';
  static const benchLeverUnderCooler =
      'The mounted cooler presses on the socket load plate. Take the cooler off before lifting the load lever.';
  static String benchRemovalNotYet(String part) =>
      '$part cannot be removed yet. Finish the work it depends on first.';

  // Orientation markers on keyed parts. The name states where the marker is
  // now, in quarter turns clockwise from 0°; it never says whether that
  // orientation fits.
  static const benchMarkerTriangle = 'Triangle';
  static const benchMarkerNotch = 'Notch';
  static const benchMarkerFan = 'Fan';
  static const benchMarkerCorners = [
    'bottom-left',
    'top-left',
    'top-right',
    'bottom-right',
  ];
  static const benchMarkerEdges = [
    'left edge',
    'top edge',
    'right edge',
    'bottom edge',
  ];
  static const benchMarkerFacings = [
    'facing down',
    'facing left',
    'facing up',
    'facing right',
  ];
  static String benchMarkerDescription(
          String marker, String position, int degrees) =>
      '$marker: $position · $degrees°';

  /// Where the marker is, without an angle. Assessment uses only this: the
  /// seating angle is the same for every keyed part, so an angle would be an
  /// answer key; matching the marker to the mark on the bench is the task.
  static String benchMarkerPosition(String marker, String position) =>
      '$marker: $position';
  static String benchRotatePositionSemantics(String part, String position) =>
      'Rotate $part by 90 degrees. $position.';
  static String benchPartMarkerSemantics(String semantics, String position) =>
      '$semantics $position.';

  /// Assessment note when a part or cable is picked up: no next-step hint.
  static String benchSelectedNeutral(String label) => '$label selected.';
  static String benchPreviewSemantics(String part, String description) =>
      '$part in hand. $description.';

  // Physical spots on the anti-static mat. They name the object, never the
  // step to take.
  static const Map<String, String> benchHotspotLabels = {
    'wear_wrist_strap': 'Wrist strap',
    'ground_wrist_strap': 'Mat ground point',
  };

  // Practice confirmation after a bench operation: what physically changed.
  static const Map<String, String> benchOperationFeedback = {
    'wear_wrist_strap': 'Wrist strap fastened on your wrist.',
    'ground_wrist_strap': 'Strap lead clipped to the mat ground point.',
    'open_cpu_lever': 'Load lever opened.',
    'close_cpu_lever': 'Load lever closed under its retention tab.',
    'apply_thermal_compound': 'Thermal compound applied to the processor.',
    'open_dimm_latches': 'DIMM latches opened.',
    'close_dimm_latches': 'DIMM latches locked.',
    'pick_screwdriver': 'Phillips screwdriver in hand.',
    'fasten_psu': 'Power-supply screws fastened.',
    'fasten_motherboard': 'Motherboard screws fastened.',
    'fasten_drive': 'Drive screws fastened.',
  };
  static const benchOperationRetest = 'Run the test to check the change.';

  // Practice guidance for the bench: it names the bench and its tray, not the
  // panels of the card workspace.
  static String guideBenchInspect(String label) =>
      'Tap $label on the bench, or its name in the tray below the bench, and read its condition.';
  static String guideBenchOperation(String label) =>
      '$label: tap its yellow ring on the bench, or its button in the tray below the bench.';
  static String guideBenchPlace(String label) =>
      'Tap $label in the tray below the bench. If it shows a gold marker, tap Rotate until the marker matches the mark on the bench. Then drag it onto its place, or tap the place or its name in the tray.';
  static String guideBenchConnect(String label) =>
      'Tap $label in the tray below the bench, then tap the header it plugs into on the bench or its name in the tray. You can also drag the connector onto the header.';
  static const guideBenchConnectPorts =
      'Tap a cable in the tray below the bench, then tap the header it plugs into on the bench or its name in the tray.';
  static const benchGuidanceInspect =
      'Tap each part on the bench, or its name in the tray below the bench, to inspect it.';
  static const benchGuidanceSelectPart =
      'Tap a part in the tray below the bench to pick it up.';
  static const benchGuidanceRotatePart =
      'If the part shows a gold marker, tap Rotate until the marker matches the mark on the board or case.';
  static const benchGuidanceDropPart =
      'Drag the part onto its place on the bench, or tap the place or its name in the tray.';
  static const benchGuidanceSelectCable =
      'Tap a cable in the tray below the bench, then tap the header it plugs into.';
  static const benchGuidanceDragCable =
      'You can also drag a connector from the tray onto its header on the bench.';
  static const benchGuidanceOperate =
      'Work the strap, levers, latches and screws on the bench: tap the yellow ring where you work, or its button in the tray below the bench.';
  static const benchGuidanceFixFaults =
      'Correct each reported fault on the bench: reseat a part, reconnect a cable, or work a lever, latch or screw. Then run the test again.';

  // Assessment mode chrome.
  static const assessmentModeLabel = 'Assessment';
  static const assessmentModeHint =
      'No hints are shown. Work as you would on the real equipment.';
  static const assessmentSubmitLabel = 'Submit assessment';
  static const assessmentSubmitTitle = 'Submit this assessment?';
  static const assessmentSubmitMessage =
      'Your recorded work is evaluated on the server. Steps you have not finished are evaluated as not satisfied, and you cannot change the work after submitting.';
  static const assessmentSubmitConfirm = 'Submit';
  static const assessmentSubmittedLabel = 'Submitted';
  static const assessmentSubmittedMessage =
      'Assessment submitted for evaluation. Your instructor releases the result.';
  static const assessmentContinueStatus =
      'Continue when you have finished this phase.';
  static const assessmentUpdateTitle = 'Update required';
  static const assessmentUpdateRequired =
      'This assessment needs the latest version of ByteQuest. Update the app, then open the assessment again.';

  // Assessment mode: neutral physical feedback that never names a target.
  static const assessmentNeutralPlacement = 'Component not seated.';
  static const assessmentNeutralRemoval = 'Nothing to remove there.';
  static const assessmentNeutralConnection = 'Connector not seated.';
  static const assessmentNeutralOperation =
      'No change — the equipment is not in a state for that action.';
  static const assessmentNeutralTool = 'No effect on the selected target.';
  static const assessmentNeutralRecorded = 'Action recorded.';

  // Assessment mode: goal-level task text, neutral part descriptions and
  // symptom-only test readouts. None of them names the slot, header, cable
  // or step that is expected; practice keeps the specific technical wording.
  static const Map<String, String> assessmentPhaseInstructions = {
    'coc1_m2_p1': 'Prepare the work area and inspect the parts before assembly.',
    'coc1_m2_p2': 'Prepare the motherboard on the anti-static mat.',
    'coc1_m2_p3': 'Install the components into the case.',
    'coc1_m2_p4': 'Connect the required power and data cables.',
    'coc1_m2_p5':
        'Power on the system, resolve any fault you observe, then interpret the result.',
  };
  static String? assessmentInstruction(String phaseId) =>
      assessmentPhaseInstructions[phaseId];

  static const Map<String, String> benchAssessmentInspection = {
    'system_case':
        'ATX mid-tower with the side panel removed. Standoffs, a rear I/O cutout, a bottom bay and a drive bay are visible.',
    'motherboard':
        'ATX motherboard on the anti-static mat: processor socket with a load lever, memory slots, fan headers, power headers, SATA ports and case headers.',
    'cpu': 'LGA processor in its tray. A gold triangle marks one corner.',
    'cooler':
        'Tower cooler without pre-applied thermal compound. It has a 4-pin fan cable.',
    'ram': 'Two identical DDR4 modules with an off-centre notch.',
    'psu':
        'ATX power supply, switched off and unplugged, with its modular power cables attached.',
    'storage':
        '3.5-inch SATA hard disk drive with separate power and data ports.',
  };

  static const assessmentReadingNominal = 'Operating normally';
  static const assessmentReadingFault = 'Fault detected';

  /// Assessment readouts that state what the technician observes, keyed
  /// `<phase>.<check>`: the COC1 M2 power-on test, and diagnostic traces whose
  /// result is the finding itself. Two causes may share one symptom (both CPU
  /// checks show the debug LED), so the learner diagnoses instead of reading
  /// the answer. Other checks read [assessmentReadingNominal] or
  /// [assessmentReadingFault].
  static const Map<String, ({String label, String nominal, String fault})>
      assessmentReadingSymptoms = {
    'coc4_m3_p4.route': (
      label: 'Route trace',
      nominal: 'Gateway 192.168.1.1 replies; hop 2 times out.',
      fault: 'No request has been traced yet.',
    ),
    'coc1_m2_p5.psu_mounting': (
      label: 'Pre-power inspection',
      nominal: 'Power supply secure.',
      fault: 'The power supply moves in its bay.',
    ),
    'coc1_m2_p5.board_mounting': (
      label: 'Pre-power inspection',
      nominal: 'Motherboard secure.',
      fault: 'The motherboard moves when it is touched.',
    ),
    'coc1_m2_p5.drive_mounting': (
      label: 'Pre-power inspection',
      nominal: 'Drive secure.',
      fault: 'The drive moves in its bay.',
    ),
    'coc1_m2_p5.power_switch': (
      label: 'Power-on',
      nominal: 'The system powers on.',
      fault: 'Pressing the case power button does nothing.',
    ),
    'coc1_m2_p5.cpu_power': (
      label: 'POST',
      nominal: 'POST passes the processor stage.',
      fault: 'No POST: the fans spin but the CPU debug LED stays lit.',
    ),
    'coc1_m2_p5.cpu_detection': (
      label: 'POST',
      nominal: 'Processor detected.',
      fault: 'No POST: the fans spin but the CPU debug LED stays lit.',
    ),
    'coc1_m2_p5.cpu_fan': (
      label: 'Cooling',
      nominal: 'CPU fan speed reported.',
      fault: 'CPU fan error at power-on.',
    ),
    'coc1_m2_p5.cpu_temperature': (
      label: 'Cooling',
      nominal: 'CPU temperature stable.',
      fault: 'CPU over-temperature warning within seconds of power-on.',
    ),
    'coc1_m2_p5.memory_detection': (
      label: 'Memory',
      nominal: 'Memory detected.',
      fault: 'Memory not detected: the DRAM debug LED is lit and the board beeps.',
    ),
    'coc1_m2_p5.memory_channels': (
      label: 'Memory',
      nominal: 'Memory is running in dual-channel mode.',
      fault: 'Memory is running in single-channel mode.',
    ),
    'coc1_m2_p5.drive_power': (
      label: 'Boot',
      nominal: 'The drive spins up.',
      fault: 'No boot device detected.',
    ),
    'coc1_m2_p5.boot_device': (
      label: 'Boot',
      nominal: 'Boot drive detected.',
      fault: 'No boot device detected.',
    ),
  };

  static String assessmentReading(
      String phaseId, String? checkId, bool operating) {
    final symptom = assessmentReadingSymptoms['$phaseId.$checkId'];
    if (symptom != null) return operating ? symptom.nominal : symptom.fault;
    return operating ? assessmentReadingNominal : assessmentReadingFault;
  }

  static String assessmentReadingLabel(
          String phaseId, String? checkId, String label) =>
      assessmentReadingSymptoms['$phaseId.$checkId']?.label ?? label;

  // A practice session saved for an earlier version of a mission.
  static const missionUpdatedTitle = 'Mission updated';
  static const missionUpdatedNotice =
      'This mission was updated. Your earlier verified result is kept; start the new version.';
  static const missionUpdatedDismiss = 'Start the new version';
  static const missionUpdateFailed =
      'This mission was updated, but the new version could not be started. Check your connection, then retry.';

  // Assembly-bench board silkscreen (printed header names on the board).
  static const benchSilkscreenCpuFan = 'CPU_FAN';
  static const benchSilkscreenSysFan = 'SYS_FAN';
  static const benchSilkscreenAtx24 = '24-PIN';
  static const benchSilkscreenEps8 = '8-PIN';
  static const benchSilkscreenFrontPanel = 'F_PANEL';
  static const placementPrerequisiteFeedback =
      'The mounting support or safety preparation is not installed yet.';
  static const occupiedDestinationFeedback =
      'This installation location is occupied. Inspect the installed component before replacing it.';
  static const sequenceConstraintFeedback =
      'This order violates a preparation or safety dependency. Inspect the procedure requirements.';
  static const operationPrerequisiteFeedback =
      'The equipment is not ready for this operation. Inspect the current state and prerequisites.';
  static const fieldFormatFeedback =
      'A configuration value has an invalid format. Check the field specification.';
  static const testResultRecordedFeedback =
      'Measured output recorded. Inspect each reading before interpreting the result.';
  static const assessmentTestRecorded = 'Measured output recorded.';
  static const confirmSequenceLabel = 'Apply procedure order';
  static const revisePhaseLabel = 'Review earlier phase';
  static const practiceHintLabel = 'Practice help';
  static const testOutputUnavailable =
      'No measured output is available for this test yet.';
  static const incompatibleToolFeedback =
      'This tool cannot engage the selected interface. Inspect the tool range and target specification.';
  static const toolContactFeedback =
      'Tool contact established with the selected target; functional verification is still required.';
  static const Map<String, String> toolObservations = {
    'anti_static_strap':
        'The wrist strap clips to the bare chassis ground point and provides the required ESD path.',
    'screwdriver':
        'The Phillips driver fits the case fastener without contacting nearby components.',
    'firmware_inventory':
        'The firmware console can enumerate the selected storage controller. Open its inventory to inspect the attached device.',
    'wire_stripper':
        'The stripping jaws engage the outer cable jacket; conductor insulation remains intact.',
    'crimping_tool':
        'The termination jaws engage the prepared connector. Continuity has not yet been verified.',
    'interface_inspection_light':
        'The interface keying and contact surfaces are visible; no bent contacts are observed.',
    'lan_loopback_adapter':
        'Loopback contacts engage the Ethernet interface. This does not verify the external network path.',
    'esd_driver':
        'The screwdriver engages the retaining-screw head without contacting the board.',
    'device_manager':
        'The device inventory contains an uninitialized peripheral. Inspect individual diagnostic records before changing a driver.',
    'port_tester':
        'The known-good probe is detected on the alternate USB port.',
    'cable_tester':
        'The selected video lead loses continuity when flexed near the connector.',
  };
  static const disconnectedToolReading =
      'No complete test circuit is connected. Connect both endpoints before interpreting continuity.';
  static const connectedToolReading =
      'A test circuit is connected. Run the wire-map procedure to inspect each conductor.';

  // Assessment mode: what the tool shows, without the next step.
  static const Map<String, String> assessmentToolObservations = {
    'anti_static_strap':
        'The wrist strap clips to the bare chassis ground point.',
    'screwdriver':
        'The Phillips driver fits the case fastener without contacting nearby components.',
    'firmware_inventory':
        'The firmware console enumerates the selected storage controller.',
    'wire_stripper':
        'The stripping jaws engage the outer cable jacket; conductor insulation remains intact.',
    'crimping_tool': 'The termination jaws engage the prepared connector.',
    'interface_inspection_light':
        'The interface keying and contact surfaces are visible; no bent contacts are observed.',
    'lan_loopback_adapter':
        'Loopback contacts engage the Ethernet interface.',
    'esd_driver':
        'The screwdriver engages the retaining-screw head without contacting the board.',
    'device_manager':
        'The device inventory contains an uninitialized peripheral.',
    'port_tester': 'The known-good probe is detected on the alternate USB port.',
    'cable_tester':
        'The selected video lead loses continuity when flexed near the connector.',
  };
  static const assessmentToolContact =
      'Tool contact established with the selected target.';
  static const assessmentDisconnectedToolReading =
      'No complete test circuit is connected.';
  static const assessmentConnectedToolReading = 'A test circuit is connected.';
  static const exitMissionTitle = 'Save and Exit Mission?';
  static const exitMissionMessage =
      'Your current mission progress will remain available when you return.';
  static const cancelExitLabel = 'Cancel';
  static const confirmExitLabel = 'Save and Exit';
  static const runtimeExitMissionTitle = 'Exit Mission?';
  static const exitMissionTooltip = 'Exit mission';
  static const runtimeExitMissionMessage =
      'Continue the mission, save your current progress, or explicitly discard this practice run.';
  static const continueMissionLabel = 'Continue Mission';
  static const discardProgressLabel = 'Discard Progress';
  static const discardProgressFailedMessage =
      'Practice progress could not be discarded. Keep the mission open and try again.';
  static const saveProgressFailedMessage =
      'Mission progress could not be saved. Keep the mission open and try again.';
  static const continueLabel = 'Continue';
  static const retryPendingEvidenceLabel = 'Retry pending evidence';
  static const retryingPendingEvidenceLabel = 'Retrying evidence…';
  static const retryingPendingEvidenceFeedback =
      'Retrying pending evidence with its original action identifier.';
  static const pendingEvidenceSynchronizedFeedback =
      'Pending evidence synchronized.';
  static const pendingEvidenceRetryFailedFeedback =
      'Pending evidence is still saved locally. Check the connection and retry.';
  static const practiceEvidenceUnavailableMessage =
      'Practice evidence capture is unavailable. Keep the mission open and retry before leaving.';
  static const practiceEvidencePendingMessage =
      'Practice evidence is saved locally but has not synchronized yet.';
  static const retryEvidenceLabel = 'Retry evidence sync';
  static const assessmentPlacementsRecordedLabel =
      'Placements recorded for review';
  static const troubleshootingDiagnosticsLabel = 'Troubleshooting diagnostics';
  static const reportedSymptomLabel = 'Reported symptom';
  static const serviceCasesLabel = 'Service cases';
  static const possibleCausesLabel = 'Possible causes';
  static const diagnosticActionsLabel = 'Diagnostic actions';
  static const recordedFindingsLabel = 'Recorded findings';
  static const inspectLabel = 'Inspect';
  static const applyCorrectionLabel = 'Apply correction';
  static const retestLabel = 'Retest';
  static const serviceCaseLabel = 'Service case';
  static const correctConnectionLabel = 'Correct';
  static const reviewConnectionLabel = 'Review';
  static const reviewOrChangePlacementsLabel = 'Review or change placements';
  static const reviewOrChangeMatchesLabel = 'Review or change matches';
  static const reviewOrChangeConnectionsLabel = 'Review or change connections';
  static const hideCompletedControlsLabel = 'Hide completed controls';
  static const recordedMatchesLabel = 'Recorded matches';

  /// Learner-visible technical feedback keyed by stable mission and feedback
  /// identifiers. Evaluation outcomes remain owned by authoritative services.
  static const Map<String, Map<String, String>> missionFeedbackCatalogs = {
    'coc1_m1': {
      'coc1_m1_constraint':
          'Inspect the component label and safety condition before recording the set.',
      'coc1_m1_evidence':
          'Readiness verification records the observed hardware state.',
      'coc1_m1_review':
          'Review the inspection, safety selection, and observation evidence before submission.',
    },
    'coc1_m2': {
      'coc1_m2_constraint':
          'Compatibility, orientation, and installation order must be recorded for each component.',
      'coc1_m2_evidence':
          'The installation check records seating and fastening observations.',
      'coc1_m2_review':
          'Review every placement and the final installation check before submission.',
    },
    'coc1_m3': {
      'coc1_m3_constraint':
          'Inspect firmware, storage destination, and driver configuration before installing and restarting.',
      'coc1_m3_evidence':
          'The test record must include the displayed result for later interpretation.',
      'coc1_m3_review':
          'Review setup, installation, driver configuration, restart, and measured verification evidence.',
    },
    'coc1_m4': {
      'coc1_m4_constraint':
          'Match the tool and connector to the inspected peripheral interface.',
      'coc1_m4_evidence':
          'Record the device-test output before interpreting peripheral status.',
      'coc1_m4_review':
          'Review inspected interfaces, connections, and test observations.',
    },
    'coc1_m5': {
      'coc1_m5_constraint':
          'Use recorded symptoms and diagnostic facts before applying a correction.',
      'coc1_m5_evidence':
          'Integration verification must follow the recorded corrective action.',
      'coc1_m5_review':
          'Review the diagnostic path, correction, and integration retest.',
    },
    'coc2_m1': {
      'coc2_m1_constraint':
          'Material, tool, and preparation evidence must precede the connection.',
      'coc2_m1_evidence':
          'Record tester output and a technical interpretation of the result.',
      'coc2_m1_review':
          'Review materials, preparation, connection, and tester evidence.',
    },
    'coc2_m2': {
      'coc2_m2_constraint':
          'Keep cable evidence identifiers and device configuration actions distinct.',
      'coc2_m2_evidence':
          'Connectivity verification records the tester and device observations.',
      'coc2_m2_review':
          'Review cable preparation, topology, configuration, and connectivity evidence.',
    },
    'coc2_m3': {
      'coc2_m3_constraint':
          'Each topology link must identify both selected endpoints.',
      'coc2_m3_evidence':
          'Run link verification again after recording the invalid-link repair.',
      'coc2_m3_review':
          'Review node selection, link construction, diagnosis, and repair evidence.',
    },
    'coc2_m4': {
      'coc2_m4_constraint':
          'Record device context with each network configuration value.',
      'coc2_m4_evidence':
          'Preserve the connectivity output before and after reconfiguration.',
      'coc2_m4_review':
          'Review configuration, interpretation, correction, and retest evidence.',
    },
    'coc2_m5': {
      'coc2_m5_constraint':
          'Reveal topology and configuration facts through diagnostic actions.',
      'coc2_m5_evidence':
          'The retest must follow a recorded network correction.',
      'coc2_m5_review':
          'Review the progressive diagnostic path and connectivity recovery.',
    },
    'coc3_m1': {
      'coc3_m1_constraint':
          'Confirm workspace, server role, and network prerequisites before setup.',
      'coc3_m1_evidence':
          'Readiness verification records the completed preparation sequence.',
      'coc3_m1_review':
          'Review requirement, role, readiness, and preparation evidence.',
    },
    'coc3_m2': {
      'coc3_m2_constraint':
          'Role and configuration decisions must be recorded before installation.',
      'coc3_m2_evidence':
          'Verify service readiness only after the simulated restart completes.',
      'coc3_m2_review':
          'Review installation choices, restart state, and service checks.',
    },
    'coc3_m3': {
      'coc3_m3_constraint':
          'Account, group, and permission changes require matching access evidence.',
      'coc3_m3_evidence':
          'Repeat the access test after recording the permission correction.',
      'coc3_m3_review':
          'Review identity configuration, diagnosis, correction, and access retest.',
    },
    'coc3_m4': {
      'coc3_m4_constraint':
          'Record configuration and service state before client testing.',
      'coc3_m4_evidence':
          'Client-test output must be preserved before interpretation.',
      'coc3_m4_review':
          'Review service configuration, status changes, and client response evidence.',
    },
    'coc3_m5': {
      'coc3_m5_constraint':
          'Inspect client, server, service, network, and permission facts progressively.',
      'coc3_m5_evidence':
          'Recovery verification must follow the selected corrective action.',
      'coc3_m5_review':
          'Review the earned facts, correction, retest, and recovery state.',
    },
    'coc4_m1': {
      'coc4_m1_constraint':
          'Base diagnostic priority on inspected symptoms and recorded observations.',
      'coc4_m1_evidence':
          'Verification records whether later observations support the preliminary diagnosis.',
      'coc4_m1_review':
          'Review inspection, priority, diagnosis, and verification evidence.',
    },
    'coc4_m2': {
      'coc4_m2_constraint':
          'Choose a diagnostic tool that can measure the inspected condition.',
      'coc4_m2_evidence':
          'Repair verification must record the post-repair test result.',
      'coc4_m2_review':
          'Review the test, interpretation, fault decision, and repair evidence.',
    },
    'coc4_m3': {
      'coc4_m3_constraint':
          'Interpret each earned diagnostic result before opening the next branch.',
      'coc4_m3_evidence':
          'Software and network findings remain separate evidence records.',
      'coc4_m3_review':
          'Review the ordered diagnostic actions and both interpretations.',
    },
    'coc4_m4': {
      'coc4_m4_constraint':
          'Record component compatibility, tool choice, and replacement sequence.',
      'coc4_m4_evidence':
          'Run the post-repair test after replacement and reconfiguration.',
      'coc4_m4_review':
          'Review replacement, configuration, sequence, and test evidence.',
    },
    'coc4_m5': {
      'coc4_m5_constraint':
          'Prioritize the service request before maintenance or repair changes.',
      'coc4_m5_evidence':
          'Final verification records the maintained configuration and test interpretation.',
      'coc4_m5_review':
          'Review the request, repair record, test evidence, and final report.',
    },
  };

  static Map<String, String> feedbackForMission(String missionId) =>
      Map.unmodifiable(missionFeedbackCatalogs[missionId] ?? const {});

  // ==========================================
  // COC 1 MISSION 1: Identify Computer Parts - WITH REAL IMAGES
  // ==========================================

  /// Hardware Items for COC 1 Mission 1
  static List<HardwareItem> getCOC1M1Items() {
    return [
      HardwareItem(
        id: 'motherboard',
        name: 'Motherboard',
        imagePath: 'assets/COC1/Mission 1/motherboard.png',
      ),
      HardwareItem(
        id: 'cpu',
        name: 'CPU',
        imagePath: 'assets/COC1/Mission 1/cpu.png',
      ),
      HardwareItem(
        id: 'ram',
        name: 'RAM',
        imagePath: 'assets/COC1/Mission 1/ram.png',
      ),
      HardwareItem(
        id: 'ssd',
        name: 'SSD',
        imagePath: 'assets/COC1/Mission 1/ssd.png',
      ),
      HardwareItem(
        id: 'hdd',
        name: 'HDD',
        imagePath: 'assets/COC1/Mission 1/hdd.png',
      ),
      HardwareItem(
        id: 'psu',
        name: 'PSU',
        imagePath: 'assets/COC1/Mission 1/psu.png',
      ),
      HardwareItem(
        id: 'keyboard',
        name: 'Keyboard',
        imagePath: 'assets/COC1/Mission 1/keyboard.png',
      ),
      HardwareItem(
        id: 'mouse',
        name: 'Mouse',
        imagePath: 'assets/COC1/Mission 1/mouse.png',
      ),
      HardwareItem(
        id: 'monitor',
        name: 'Monitor',
        imagePath: 'assets/COC1/Mission 1/monitor.png',
      ),
      HardwareItem(
        id: 'screwdriver',
        name: 'Screwdriver',
        imagePath: 'assets/COC1/Mission 1/screwdriver.png',
      ),
      HardwareItem(
        id: 'anti_static_strap',
        name: 'Anti-static Strap',
        imagePath: 'assets/COC1/Mission 1/anti_static_wrist_strap.png',
      ),
      HardwareItem(id: 'not_sure', name: 'Not sure', imagePath: ''),
    ];
  }

  /// Questions for COC 1 Mission 1 - Using Image-Based Identification
  static List<MissionQuestion> getCOC1M1Questions() {
    return [
      MissionQuestion(
        id: 'q1',
        question: 'Select the RAM (Random Access Memory)',
        options: [
          'Motherboard',
          'CPU',
          'RAM',
          'SSD',
          'HDD',
          'PSU',
          'Keyboard',
          'Mouse',
          'Monitor',
          'Screwdriver',
          'Anti-static Strap',
          'Not sure',
        ],
        correctAnswer: 'RAM',
        explanation:
            'RAM is the temporary memory where data is stored for quick access by the CPU.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q2',
        question: 'Select the Power Supply Unit (PSU)',
        options: [
          'Motherboard',
          'CPU',
          'RAM',
          'SSD',
          'HDD',
          'PSU',
          'Keyboard',
          'Mouse',
          'Monitor',
          'Screwdriver',
          'Anti-static Strap',
          'Not sure',
        ],
        correctAnswer: 'PSU',
        explanation:
            'The PSU converts AC power to DC power for computer components.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q3',
        question: 'Select the Anti-static Strap',
        options: [
          'Motherboard',
          'CPU',
          'RAM',
          'SSD',
          'HDD',
          'PSU',
          'Keyboard',
          'Mouse',
          'Monitor',
          'Screwdriver',
          'Anti-static Strap',
          'Not sure',
        ],
        correctAnswer: 'Anti-static Strap',
        explanation:
            'Anti-static wrist straps prevent static electricity from damaging components.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q4',
        question: 'Select the Motherboard',
        options: [
          'Motherboard',
          'CPU',
          'RAM',
          'SSD',
          'HDD',
          'PSU',
          'Keyboard',
          'Mouse',
          'Monitor',
          'Screwdriver',
          'Anti-static Strap',
          'Not sure',
        ],
        correctAnswer: 'Motherboard',
        explanation:
            'The motherboard is the main circuit board that connects all components.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q5',
        question: 'Select the Central Processing Unit (CPU)',
        options: [
          'Motherboard',
          'CPU',
          'RAM',
          'SSD',
          'HDD',
          'PSU',
          'Keyboard',
          'Mouse',
          'Monitor',
          'Screwdriver',
          'Anti-static Strap',
          'Not sure',
        ],
        correctAnswer: 'CPU',
        explanation:
            'The CPU is the brain of the computer that processes instructions.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q6',
        question: 'Select the Solid State Drive (SSD)',
        options: [
          'Motherboard',
          'CPU',
          'RAM',
          'SSD',
          'HDD',
          'PSU',
          'Keyboard',
          'Mouse',
          'Monitor',
          'Screwdriver',
          'Anti-static Strap',
          'Not sure',
        ],
        correctAnswer: 'SSD',
        explanation:
            'SSDs are fast storage devices that permanently store data.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q7',
        question: 'Select the Hard Disk Drive (HDD)',
        options: [
          'Motherboard',
          'CPU',
          'RAM',
          'SSD',
          'HDD',
          'PSU',
          'Keyboard',
          'Mouse',
          'Monitor',
          'Screwdriver',
          'Anti-static Strap',
          'Not sure',
        ],
        correctAnswer: 'HDD',
        explanation:
            'HDDs are traditional magnetic storage devices used for large volumes of data.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q8',
        question: 'Select the Screwdriver',
        options: [
          'Motherboard',
          'CPU',
          'RAM',
          'SSD',
          'HDD',
          'PSU',
          'Keyboard',
          'Mouse',
          'Monitor',
          'Screwdriver',
          'Anti-static Strap',
          'Not sure',
        ],
        correctAnswer: 'Screwdriver',
        explanation:
            'Screwdrivers are essential tools for assembling computers.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q9',
        question: 'Select the Monitor',
        options: [
          'Motherboard',
          'CPU',
          'RAM',
          'SSD',
          'HDD',
          'PSU',
          'Keyboard',
          'Mouse',
          'Monitor',
          'Screwdriver',
          'Anti-static Strap',
          'Not sure',
        ],
        correctAnswer: 'Monitor',
        explanation:
            'The monitor is the display device that shows visual output.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q10',
        question: 'Select the Keyboard',
        options: [
          'Motherboard',
          'CPU',
          'RAM',
          'SSD',
          'HDD',
          'PSU',
          'Keyboard',
          'Mouse',
          'Monitor',
          'Screwdriver',
          'Anti-static Strap',
          'Not sure',
        ],
        correctAnswer: 'Keyboard',
        explanation:
            'A keyboard is an input device used to type text and commands into the computer.',
        points: 10,
      ),
    ];
  }

  // ==========================================
  // COC 1 MISSION 2: Install Internal Components
  // ==========================================
  static List<DraggableComponent> getCOC1M2Components() {
    return [
      DraggableComponent(
        id: 'motherboard',
        name: 'Motherboard',
        targetZone: 'case',
        description: 'Install motherboard into the case first',
      ),
      DraggableComponent(
        id: 'cpu',
        name: 'CPU',
        targetZone: 'cpu_socket',
        description: 'Place CPU into the CPU socket on motherboard',
      ),
      DraggableComponent(
        id: 'cpu_cooler',
        name: 'CPU Cooler',
        targetZone: 'cpu_area',
        description: 'Install cooling fan on top of CPU',
      ),
      DraggableComponent(
        id: 'ram',
        name: 'RAM Module',
        targetZone: 'ram_slot',
        description: 'Insert RAM into memory slots',
      ),
      DraggableComponent(
        id: 'storage',
        name: 'Storage Drive',
        targetZone: 'drive_bay',
        description: 'Mount storage device in drive bay',
      ),
    ];
  }

  static List<DropZone> getCOC1M2DropZones() {
    return [
      DropZone(
        id: 'case',
        name: 'System Unit Case',
        acceptedComponents: ['motherboard'],
      ),
      DropZone(
        id: 'cpu_socket',
        name: 'CPU Socket',
        acceptedComponents: ['cpu'],
      ),
      DropZone(
        id: 'cpu_area',
        name: 'CPU Cooling Area',
        acceptedComponents: ['cpu_cooler'],
      ),
      DropZone(id: 'ram_slot', name: 'RAM Slots', acceptedComponents: ['ram']),
      DropZone(
        id: 'drive_bay',
        name: 'Drive Bay',
        acceptedComponents: ['storage'],
      ),
    ];
  }

  // ==========================================
  // COC 1 MISSION 3: Connect Power and Data Cables
  // ==========================================
  static List<DraggableComponent> getCOC1M3Components() {
    return [
      DraggableComponent(
        id: '24pin_cable',
        name: '24-Pin ATX Cable',
        targetZone: 'motherboard_power',
        description: 'Main power connector for motherboard',
      ),
      DraggableComponent(
        id: 'cpu_power',
        name: 'CPU Power Cable',
        targetZone: 'cpu_power_port',
        description: '4-pin or 8-pin CPU power connector',
      ),
      DraggableComponent(
        id: 'sata_data',
        name: 'SATA Data Cable',
        targetZone: 'storage_data',
        description: 'Connects storage to motherboard',
      ),
      DraggableComponent(
        id: 'sata_power',
        name: 'SATA Power Cable',
        targetZone: 'storage_power',
        description: 'Powers the storage device',
      ),
      DraggableComponent(
        id: 'front_panel',
        name: 'Front Panel Connector',
        targetZone: 'front_panel_pins',
        description: 'Connects case buttons and LEDs',
      ),
    ];
  }

  static List<DropZone> getCOC1M3DropZones() {
    return [
      DropZone(
        id: 'motherboard_power',
        name: 'Motherboard 24-Pin Port',
        acceptedComponents: ['24pin_cable'],
      ),
      DropZone(
        id: 'cpu_power_port',
        name: 'CPU Power Port',
        acceptedComponents: ['cpu_power'],
      ),
      DropZone(
        id: 'storage_data',
        name: 'Storage SATA Port',
        acceptedComponents: ['sata_data'],
      ),
      DropZone(
        id: 'storage_power',
        name: 'Storage Power Port',
        acceptedComponents: ['sata_power'],
      ),
      DropZone(
        id: 'front_panel_pins',
        name: 'Front Panel Header',
        acceptedComponents: ['front_panel'],
      ),
    ];
  }

  // ==========================================
  // COC 1 MISSION 4: Configure BIOS
  // ==========================================
  static Map<String, dynamic> getCOC1M4ConfigData() {
    return {
      'bootPriority': {
        'question': 'Set the correct boot device priority',
        'options': ['Hard Drive', 'USB Drive', 'CD/DVD Drive', 'Network'],
        'correctAnswer': 'Hard Drive',
        'points': 20,
      },
      'detectedHardware': {
        'question': 'Verify all hardware is detected',
        'items': ['CPU', 'RAM', 'Storage', 'Network Card'],
        'correctAnswer': 'CPU, RAM, Storage, Network Card',
        'points': 20,
      },
      'osInstallation': {
        'question':
            'Configure BIOS settings correctly and follow the proper sequence for operating system installation.',
        'steps': [
          'Select language and keyboard',
          'Accept license agreement',
          'Choose installation type',
          'Select partition/drive',
          'Begin installation',
          'Set up user account',
          'Complete setup',
        ],
        'correctAnswer':
            'Select language and keyboard, Accept license agreement, Choose installation type, Select partition/drive, Begin installation, Set up user account, Complete setup',
        'points': 40,
      },
    };
  }

  // ==========================================
  // COC 1 MISSION 5: Install Drivers and Test
  // ==========================================
  static List<ProcedureStep> getCOC1M5Steps() {
    return [
      ProcedureStep(
        id: 'step1',
        order: 1,
        title: 'Install LAN Driver',
        description: 'Install network adapter driver for internet connectivity',
        points: 10,
      ),
      ProcedureStep(
        id: 'step2',
        order: 2,
        title: 'Install Audio Driver',
        description: 'Install sound card driver for audio functionality',
        points: 10,
      ),
      ProcedureStep(
        id: 'step3',
        order: 3,
        title: 'Install Graphics Driver',
        description: 'Install display adapter driver for optimal graphics',
        points: 10,
      ),
      ProcedureStep(
        id: 'step4',
        order: 4,
        title: 'Install Chipset Driver',
        description: 'Install motherboard chipset driver',
        points: 10,
      ),
      ProcedureStep(
        id: 'step5',
        order: 5,
        title: 'Test Display',
        description: 'Verify monitor displays correctly',
        points: 10,
      ),
      ProcedureStep(
        id: 'step6',
        order: 6,
        title: 'Test Keyboard',
        description: 'Verify keyboard input works',
        points: 10,
      ),
      ProcedureStep(
        id: 'step7',
        order: 7,
        title: 'Test Mouse',
        description: 'Verify mouse pointer movement and clicks',
        points: 10,
      ),
      ProcedureStep(
        id: 'step8',
        order: 8,
        title: 'Test Audio',
        description: 'Play test sound to verify audio output',
        points: 10,
      ),
      ProcedureStep(
        id: 'step9',
        order: 9,
        title: 'Test Network',
        description: 'Connect to network and test internet access',
        points: 10,
      ),
      ProcedureStep(
        id: 'step10',
        order: 10,
        title: 'Verify All Tests Passed',
        description: 'Confirm all hardware tests completed successfully',
        points: 10,
      ),
    ];
  }

  /// Hardware Items for COC 2 Mission 1
  static List<HardwareItem> getCOC2M1Items() {
    return [
      HardwareItem(
        id: 'router',
        name: 'Router',
        imagePath: 'assets/COC2/Mission 1/Router.png',
      ),
      HardwareItem(
        id: 'switch',
        name: 'Switch',
        imagePath: 'assets/COC2/Mission 1/Switch.png',
      ),
      HardwareItem(
        id: 'modem',
        name: 'Modem',
        imagePath: 'assets/COC2/Mission 1/Modem.png',
      ),
      HardwareItem(
        id: 'lan_cable',
        name: 'LAN Cable',
        imagePath: 'assets/COC2/Mission 1/Lan Cable.png',
      ),
      HardwareItem(
        id: 'rj45_connector',
        name: 'RJ45 Connector',
        imagePath: 'assets/COC2/Mission 1/RJ45 Connector.png',
      ),
      HardwareItem(
        id: 'nic',
        name: 'NIC',
        imagePath: 'assets/COC2/Mission 1/NIC.png',
      ),
      HardwareItem(
        id: 'crimping_tool',
        name: 'Crimping Tool',
        imagePath: 'assets/COC2/Mission 1/Crimping Tool.png',
      ),
      HardwareItem(
        id: 'wire_stripper',
        name: 'Wire Stripper',
        imagePath: 'assets/COC2/Mission 1/Wire Stripper.png',
      ),
      HardwareItem(
        id: 'lan_tester',
        name: 'LAN Tester',
        imagePath: 'assets/COC2/Mission 1/LAN Tester.png',
      ),
    ];
  }

  // ==========================================
  // COC 2 MISSION 1: Identify Network Devices
  // ==========================================
  static List<MissionQuestion> getCOC2M1Questions() {
    final allOptions = [
      'Router',
      'Switch',
      'Modem',
      'LAN Cable',
      'RJ45 Connector',
      'NIC',
      'Crimping Tool',
      'Wire Stripper',
      'LAN Tester',
    ];

    return [
      MissionQuestion(
        id: 'q1',
        question: 'Select the Router',
        options: allOptions,
        correctAnswer: 'Router',
        explanation:
            'A router connects multiple networks and directs traffic between them.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q2',
        question: 'Select the Network Switch',
        options: allOptions,
        correctAnswer: 'Switch',
        explanation: 'A switch connects devices within a single network.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q3',
        question: 'Select the Modem',
        options: allOptions,
        correctAnswer: 'Modem',
        explanation:
            'A modem converts digital signals for internet transmission.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q4',
        question: 'Select the LAN Cable (Ethernet Cable)',
        options: allOptions,
        correctAnswer: 'LAN Cable',
        explanation:
            'LAN cables (Cat5e/Cat6) are used for wired network connections.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q5',
        question: 'Select the RJ45 Connector',
        options: allOptions,
        correctAnswer: 'RJ45 Connector',
        explanation: 'RJ45 is the standard connector for Ethernet cables.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q6',
        question: 'Select the Network Interface Card (NIC)',
        options: allOptions,
        correctAnswer: 'NIC',
        explanation: 'NIC allows a computer to connect to a network.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q7',
        question: 'Select the Crimping Tool',
        options: allOptions,
        correctAnswer: 'Crimping Tool',
        explanation: 'Crimping tools attach RJ45 connectors to cables.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q8',
        question: 'Select the Wire Stripper',
        options: allOptions,
        correctAnswer: 'Wire Stripper',
        explanation: 'Wire strippers remove cable insulation.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q9',
        question: 'Select the LAN Cable Tester',
        options: allOptions,
        correctAnswer: 'LAN Tester',
        explanation: 'LAN testers verify cable connectivity and wiring.',
        points: 10,
      ),
    ];
  }

  // ==========================================
  // COC 2 MISSION 2: Create Network Cables (T568B)
  // ==========================================
  static List<String> getCOC2M2WireSequence() {
    return [
      'White-Orange',
      'Orange',
      'White-Green',
      'Blue',
      'White-Blue',
      'Green',
      'White-Brown',
      'Brown',
    ];
  }

  // ==========================================
  // COC 2 MISSION 3: Test Cable
  // ==========================================
  static List<ProcedureStep> getCOC2M3Steps() {
    return [
      ProcedureStep(
        id: 'step1',
        order: 1,
        title: 'Connect Cable to Tester',
        description: 'Plug both ends of cable into LAN tester ports',
        points: 20,
      ),
      ProcedureStep(
        id: 'step2',
        order: 2,
        title: 'Power On Tester',
        description: 'Turn on the LAN cable tester',
        points: 20,
      ),
      ProcedureStep(
        id: 'step3',
        order: 3,
        title: 'Observe Light Sequence',
        description: 'Watch the LED indicators light up in sequence (1-8)',
        points: 30,
      ),
      ProcedureStep(
        id: 'step4',
        order: 4,
        title: 'Verify Results',
        description:
            'Check if all 8 lights blink in correct order (Pass) or identify faults',
        points: 30,
      ),
    ];
  }

  // ==========================================
  // COC 2 MISSION 4: Connect LAN Devices
  // ==========================================
  static List<DraggableComponent> getCOC2M4Components() {
    return [
      DraggableComponent(
        id: 'computer',
        name: 'Computer',
        targetZone: 'switch_port',
        description: 'Connect computer to switch',
      ),
      DraggableComponent(
        id: 'switch',
        name: 'Network Switch',
        targetZone: 'router_lan',
        description: 'Connect switch to router',
      ),
      DraggableComponent(
        id: 'router',
        name: 'Router',
        targetZone: 'modem',
        description: 'Connect router to modem',
      ),
    ];
  }

  // ==========================================
  // COC 2 MISSION 5: Configure IP Settings
  // ==========================================
  static Map<String, dynamic> getCOC2M5ConfigData() {
    return {
      'ipAddress': {
        'question': 'Enter a valid IP Address',
        'correctAnswer': '192.168.1.100',
        'validation':
            r'^192\.168\.1\.(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$',
        'points': 25,
      },
      'subnetMask': {
        'question': 'Enter the Subnet Mask',
        'correctAnswer': '255.255.255.0',
        'validation': r'^255\.255\.255\.0$',
        'points': 25,
      },
      'gateway': {
        'question': 'Enter the Default Gateway',
        'correctAnswer': '192.168.1.1',
        'validation': r'^192\.168\.1\.1$',
        'points': 25,
      },
      'dns': {
        'question': 'Enter the DNS Server',
        'correctAnswer': '8.8.8.8',
        'validation': r'^8\.8\.8\.8$',
        'points': 25,
      },
    };
  }

  // ==========================================
  // COC 3 MISSION 1: Server Setup Requirements
  // ==========================================
  static List<MissionQuestion> getCOC3M1Questions() {
    return [
      MissionQuestion(
        id: 'q1',
        question: 'Select Server Hardware',
        options: ['Gaming PC', 'Server Hardware', 'Laptop', 'Tablet'],
        correctAnswer: 'Server Hardware',
        explanation:
            'Server-grade hardware is designed for reliability and performance.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q2',
        question: 'Select Client Computer',
        options: ['Server', 'Client Computer', 'Router', 'Switch'],
        correctAnswer: 'Client Computer',
        explanation: 'Client computers access server resources.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q3',
        question: 'Select Server OS Installer',
        options: [
          'Game Disc',
          'Server OS Installer',
          'Application CD',
          'Driver Disc',
        ],
        correctAnswer: 'Server OS Installer',
        explanation:
            'Server OS installer contains the server operating system.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q4',
        question: 'Select Network Connection',
        options: ['Bluetooth', 'Network Connection', 'USB Cable', 'HDMI'],
        correctAnswer: 'Network Connection',
        explanation: 'Network connection enables client-server communication.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q5',
        question: 'Select Configuration Checklist',
        options: [
          'User Manual',
          'Configuration Checklist',
          'Warranty Card',
          'Receipt',
        ],
        correctAnswer: 'Configuration Checklist',
        explanation: 'Checklist ensures all setup steps are completed.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q6',
        question: 'Select UPS (Uninterruptible Power Supply)',
        options: ['Power Strip', 'UPS', 'Extension Cord', 'Adapter'],
        correctAnswer: 'UPS',
        explanation: 'UPS provides backup power during outages.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q7',
        question: 'Select Network Cables',
        options: ['HDMI Cable', 'Network Cables', 'USB Cable', 'Audio Cable'],
        correctAnswer: 'Network Cables',
        explanation: 'Network cables connect server to network infrastructure.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q8',
        question: 'Select Server Rack (if applicable)',
        options: ['Desk', 'Server Rack', 'Shelf', 'Floor'],
        correctAnswer: 'Server Rack',
        explanation: 'Server racks organize and secure server equipment.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q9',
        question: 'Select Backup Storage',
        options: ['USB Flash Drive', 'Backup Storage', 'SD Card', 'Phone'],
        correctAnswer: 'Backup Storage',
        explanation: 'Backup storage protects against data loss.',
        points: 10,
      ),
      MissionQuestion(
        id: 'q10',
        question: 'Select Documentation',
        options: ['Magazine', 'Server Documentation', 'Novel', 'Poster'],
        correctAnswer: 'Server Documentation',
        explanation: 'Documentation guides server setup and configuration.',
        points: 10,
      ),
    ];
  }

  // ==========================================
  // COC 3 MISSION 2: Install Server OS
  // ==========================================
  static List<ProcedureStep> getCOC3M2Steps() {
    return [
      ProcedureStep(
        id: 'step1',
        order: 1,
        title: 'Boot from Installer',
        description: 'Insert installer and boot from installation media',
        points: 10,
      ),
      ProcedureStep(
        id: 'step2',
        order: 2,
        title: 'Accept License Agreement',
        description: 'Read and accept the software license terms',
        points: 10,
      ),
      ProcedureStep(
        id: 'step3',
        order: 3,
        title: 'Choose Installation Type',
        description: 'Select clean installation or upgrade',
        points: 15,
      ),
      ProcedureStep(
        id: 'step4',
        order: 4,
        title: 'Select Installation Drive',
        description: 'Choose the drive where server OS will be installed',
        points: 15,
      ),
      ProcedureStep(
        id: 'step5',
        order: 5,
        title: 'Set Server Name',
        description: 'Enter a descriptive name for the server',
        points: 10,
      ),
      ProcedureStep(
        id: 'step6',
        order: 6,
        title: 'Configure Time Zone',
        description: 'Set the correct time zone for server location',
        points: 10,
      ),
      ProcedureStep(
        id: 'step7',
        order: 7,
        title: 'Create Administrator Account',
        description: 'Set up administrator username and password',
        points: 15,
      ),
      ProcedureStep(
        id: 'step8',
        order: 8,
        title: 'Complete Installation',
        description: 'Wait for installation to finish and restart',
        points: 15,
      ),
    ];
  }

  // ==========================================
  // COC 4 MISSION 1: Identify Problems
  // ==========================================
  static List<Map<String, dynamic>> getCOC4M1Scenarios() {
    return [
      {
        'symptom': 'No display on monitor',
        'causes': [
          'Loose display cable',
          'RAM not seated',
          'Power issue',
          'Broken mouse',
        ],
        'correctCause': 'Loose display cable',
        'points': 10,
      },
      {
        'symptom': 'Computer is very slow',
        'causes': [
          'Too many startup programs',
          'Low storage space',
          'Good RAM',
          'Fast CPU',
        ],
        'correctCause': 'Too many startup programs',
        'points': 10,
      },
      {
        'symptom': 'No internet connection',
        'causes': [
          'Wrong IP address',
          'Correct DNS',
          'Good cable',
          'Fast speed',
        ],
        'correctCause': 'Wrong IP address',
        'points': 10,
      },
      {
        'symptom': 'Computer overheating',
        'causes': [
          'Clean fans',
          'Dusty cooling fan',
          'Good airflow',
          'Low temperature',
        ],
        'correctCause': 'Dusty cooling fan',
        'points': 10,
      },
      {
        'symptom': 'Cannot print documents',
        'causes': [
          'Printer driver missing',
          'Paper loaded',
          'Ink full',
          'Cable connected',
        ],
        'correctCause': 'Printer driver missing',
        'points': 10,
      },
      {
        'symptom': 'Blue screen errors',
        'causes': ['Faulty RAM', 'Good drivers', 'Clean system', 'Fast SSD'],
        'correctCause': 'Faulty RAM',
        'points': 10,
      },
      {
        'symptom': 'System won\'t boot',
        'causes': [
          'Wrong boot order',
          'Good BIOS',
          'Detected HDD',
          'Working PSU',
        ],
        'correctCause': 'Wrong boot order',
        'points': 10,
      },
      {
        'symptom': 'No sound output',
        'causes': [
          'Audio driver issue',
          'Good speakers',
          'Volume up',
          'Cable OK',
        ],
        'correctCause': 'Audio driver issue',
        'points': 10,
      },
      {
        'symptom': 'Keyboard not working',
        'causes': [
          'USB port issue',
          'Good connection',
          'Clean keys',
          'New keyboard',
        ],
        'correctCause': 'USB port issue',
        'points': 10,
      },
      {
        'symptom': 'Network is very slow',
        'causes': [
          'Network congestion',
          'Fast router',
          'Good cable',
          'Strong signal',
        ],
        'correctCause': 'Network congestion',
        'points': 10,
      },
    ];
  }

  /// Project-approved COC4 M5 service queue retained from the original
  /// ByteQuest mission. These are practice troubleshooting cases, not TESDA
  /// scoring rules; [points] is preserved only for legacy content parity and
  /// is never used for authoritative evaluation.
  static List<Map<String, dynamic>> getCOC4M5Scenarios() {
    return const [
      {
        'id': 'printer_driver',
        'symptom': 'Printer not printing',
        'causes': [
          'Driver not installed',
          'Paper loaded',
          'Ink full',
          'Power on',
        ],
        'correctCause': 'Driver not installed',
        'explanation': 'Install the correct printer driver.',
        'points': 20,
      },
      {
        'id': 'usb_port',
        'symptom': 'USB device not recognized',
        'causes': [
          'USB port damaged',
          'Device working',
          'Cable good',
          'Driver present',
        ],
        'correctCause': 'USB port damaged',
        'explanation': 'Try a different USB port.',
        'points': 20,
      },
      {
        'id': 'audio_driver',
        'symptom': 'Audio not working',
        'causes': [
          'Audio driver missing',
          'Speakers on',
          'Volume up',
          'Cable connected',
        ],
        'correctCause': 'Audio driver missing',
        'explanation': 'Install or update the audio driver.',
        'points': 20,
      },
      {
        'id': 'video_cable',
        'symptom': 'Monitor shows "No Signal"',
        'causes': [
          'Video cable disconnected',
          'Monitor on',
          'Computer on',
          'GPU installed',
        ],
        'correctCause': 'Video cable disconnected',
        'explanation': 'Reconnect the video cable securely.',
        'points': 20,
      },
      {
        'id': 'windows_update',
        'symptom': 'System slow after Windows update',
        'causes': [
          'Background updates running',
          'Good RAM',
          'Fast SSD',
          'Clean system',
        ],
        'correctCause': 'Background updates running',
        'explanation': 'Wait for updates to complete or restart the system.',
        'points': 20,
      },
    ];
  }

  // ==========================================
  // COC 4 MISSION 2: Preventive Maintenance
  // ==========================================
  static List<ProcedureStep> getCOC4M2Steps() {
    return [
      ProcedureStep(
        id: 'step1',
        order: 1,
        title: 'Turn Off Computer',
        description: 'Shut down the system properly',
        points: 10,
      ),
      ProcedureStep(
        id: 'step2',
        order: 2,
        title: 'Unplug Power Cable',
        description: 'Disconnect power to ensure safety',
        points: 10,
      ),
      ProcedureStep(
        id: 'step3',
        order: 3,
        title: 'Wear Anti-Static Protection',
        description: 'Put on anti-static wrist strap',
        points: 10,
      ),
      ProcedureStep(
        id: 'step4',
        order: 4,
        title: 'Open System Case',
        description: 'Remove side panel to access components',
        points: 10,
      ),
      ProcedureStep(
        id: 'step5',
        order: 5,
        title: 'Clean Dust with Compressed Air',
        description: 'Blow dust from components and fans',
        points: 10,
      ),
      ProcedureStep(
        id: 'step6',
        order: 6,
        title: 'Check Cooling Fans',
        description: 'Verify fans spin freely and are clean',
        points: 10,
      ),
      ProcedureStep(
        id: 'step7',
        order: 7,
        title: 'Inspect Cables',
        description: 'Check all cables are secure and organized',
        points: 10,
      ),
      ProcedureStep(
        id: 'step8',
        order: 8,
        title: 'Reseat Components',
        description: 'Ensure RAM and cards are properly seated',
        points: 10,
      ),
      ProcedureStep(
        id: 'step9',
        order: 9,
        title: 'Close Case',
        description: 'Replace side panel and secure screws',
        points: 10,
      ),
      ProcedureStep(
        id: 'step10',
        order: 10,
        title: 'Test System',
        description: 'Power on and verify everything works',
        points: 10,
      ),
    ];
  }
}
