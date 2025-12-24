import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

// LaTeX text widget
class LatexText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const LatexText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final defaultStyle = style ?? const TextStyle(fontSize: 14, color: Color(0xFF374151));
    final regex = RegExp(r'\\\((.*?)\\\)');
    final matches = regex.allMatches(text);
    
    if (matches.isEmpty) return Text(text, style: defaultStyle);

    List<InlineSpan> spans = [];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start), style: defaultStyle));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(match.group(1)!, textStyle: defaultStyle.copyWith(fontSize: (defaultStyle.fontSize ?? 14) + 1)),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: defaultStyle));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

// Data Models
class Statement {
  final String text;
  final String type;
  Statement({required this.text, required this.type});
  factory Statement.fromJson(Map<String, dynamic> json) => Statement(text: json['text'], type: json['type']);
}

class SolutionStep {
  final int step;
  final String title;
  final String? content;
  final String? intro;
  final String? question;
  final List<String>? options;
  final int? correctOption;
  final String? explanation;
  bool get isQuiz => question != null;

  SolutionStep({required this.step, required this.title, this.content, this.intro, this.question, this.options, this.correctOption, this.explanation});

  factory SolutionStep.fromJson(Map<String, dynamic> json) => SolutionStep(
    step: json['step'], title: json['title'], content: json['content'], intro: json['intro'],
    question: json['question'], options: json['options'] != null ? List<String>.from(json['options']) : null,
    correctOption: json['correctOption'], explanation: json['explanation'],
  );
}

class Question {
  final int id;
  final String? topic;
  final String question;
  final List<String> options;
  final int correctAnswer;
  final Map<String, String>? breakdown;
  final List<Statement>? statements;
  final List<String>? keyInsight;
  final List<SolutionStep> solutionSteps;

  Question({required this.id, this.topic, required this.question, required this.options, required this.correctAnswer, 
    this.breakdown, this.statements, this.keyInsight, required this.solutionSteps});

  factory Question.fromJson(Map<String, dynamic> json) {
    final solutionJson = json['solution']['steps'] as List;
    return Question(
      id: json['id'], topic: json['topic'], question: json['question'],
      options: List<String>.from(json['options']), correctAnswer: json['correctAnswer'],
      breakdown: json['breakdown'] != null ? Map<String, String>.from(json['breakdown']) : null,
      statements: json['statements'] != null ? (json['statements'] as List).map((s) => Statement.fromJson(s)).toList() : null,
      keyInsight: json['keyInsight'] != null ? List<String>.from(json['keyInsight']) : null,
      solutionSteps: solutionJson.map((s) => SolutionStep.fromJson(s)).toList(),
    );
  }
}

class QuizData {
  final String topic;
  final int totalQuestions;
  final List<Question> questions;
  QuizData({required this.topic, required this.totalQuestions, required this.questions});
  factory QuizData.fromJson(Map<String, dynamic> json) {
    final questionsJson = json['questions'] as List;
    return QuizData(topic: json['topic'], totalQuestions: json['totalQuestions'], 
      questions: questionsJson.map((q) => Question.fromJson(q)).toList());
  }
}

enum HintLevel { none, breakdown, statements, insight, solution }

class TutorHomeScreen extends StatefulWidget {
  const TutorHomeScreen({super.key});
  @override
  State<TutorHomeScreen> createState() => _TutorHomeScreenState();
}

class _TutorHomeScreenState extends State<TutorHomeScreen> {
  QuizData? quizData;
  int currentQuestionIndex = 0;
  int? selectedOption;
  bool showResult = false;
  bool isLoading = true;
  HintLevel currentHintLevel = HintLevel.none;
  int currentSolutionStep = 0;
  Map<int, int?> stepAnswers = {};
  Map<int, bool> stepCompleted = {};
  Map<int, String?> statementAnswers = {};
  bool statementsChecked = false;
  
  // Draggable button position
  Offset fabPosition = const Offset(20, 500);
  
  // "Let me solve" popup state
  bool showSolvePopup = false;
  int? popupSelectedOption;
  bool popupAnswered = false;
  
  // Per-question state persistence
  Map<int, Map<String, dynamic>> questionStates = {};

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/questions.json');
      setState(() {
        quizData = QuizData.fromJson(json.decode(jsonString));
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => isLoading = false);
    }
  }

  Question? get currentQuestion => quizData?.questions[currentQuestionIndex];

  void _selectOption(int i) { if (!showResult) setState(() => selectedOption = i); }
  void _checkAnswer() { if (selectedOption != null) setState(() => showResult = true); }
  
  void _saveCurrentState() {
    questionStates[currentQuestionIndex] = {
      'selectedOption': selectedOption,
      'showResult': showResult,
      'currentHintLevel': currentHintLevel.index,
      'currentSolutionStep': currentSolutionStep,
      'stepAnswers': Map<int, int?>.from(stepAnswers),
      'stepCompleted': Map<int, bool>.from(stepCompleted),
      'statementAnswers': Map<int, String?>.from(statementAnswers),
      'statementsChecked': statementsChecked,
    };
  }
  
  void _restoreState(int questionIndex) {
    final state = questionStates[questionIndex];
    if (state != null) {
      selectedOption = state['selectedOption'];
      showResult = state['showResult'] ?? false;
      currentHintLevel = HintLevel.values[state['currentHintLevel'] ?? 0];
      currentSolutionStep = state['currentSolutionStep'] ?? 0;
      stepAnswers = Map<int, int?>.from(state['stepAnswers'] ?? {});
      stepCompleted = Map<int, bool>.from(state['stepCompleted'] ?? {});
      statementAnswers = Map<int, String?>.from(state['statementAnswers'] ?? {});
      statementsChecked = state['statementsChecked'] ?? false;
    } else {
      _resetState();
    }
    showSolvePopup = false;
    popupSelectedOption = null;
    popupAnswered = false;
  }
  
  void _nextQuestion() {
    if (quizData != null && currentQuestionIndex < quizData!.questions.length - 1) {
      _saveCurrentState();
      setState(() { 
        currentQuestionIndex++; 
        _restoreState(currentQuestionIndex);
      });
    }
  }
  
  void _previousQuestion() {
    if (currentQuestionIndex > 0) {
      _saveCurrentState();
      setState(() { 
        currentQuestionIndex--; 
        _restoreState(currentQuestionIndex);
      });
    }
  }

  void _resetState() {
    selectedOption = null; showResult = false; currentHintLevel = HintLevel.none;
    currentSolutionStep = 0; stepAnswers = {}; stepCompleted = {};
    statementAnswers = {}; statementsChecked = false;
    showSolvePopup = false; popupSelectedOption = null; popupAnswered = false;
  }

  // "Let me solve" popup methods
  void _openSolvePopup() => setState(() { showSolvePopup = true; popupSelectedOption = null; popupAnswered = false; });
  void _closeSolvePopup() => setState(() => showSolvePopup = false);
  void _selectPopupOption(int i) { if (!popupAnswered) setState(() => popupSelectedOption = i); }
  void _checkPopupAnswer() {
    if (popupSelectedOption != null) {
      setState(() {
        popupAnswered = true;
        // If correct, also mark the main question as answered
        if (popupSelectedOption == currentQuestion!.correctAnswer) {
          selectedOption = popupSelectedOption;
          showResult = true;
        }
      });
    }
  }

  void _selectStatementType(int i, String t) { if (!statementsChecked) setState(() => statementAnswers[i] = t); }
  void _checkStatements() => setState(() => statementsChecked = true);
  
  int _getStatementScore() {
    if (currentQuestion?.statements == null) return 0;
    int c = 0;
    for (int i = 0; i < currentQuestion!.statements!.length; i++) {
      if (statementAnswers[i] == currentQuestion!.statements![i].type) c++;
    }
    return c;
  }

  void _selectStepOption(int si, int oi) {
    if (stepCompleted[si] != true) setState(() => stepAnswers[si] = oi);
  }

  void _checkStepAnswer(int si) {
    final step = currentQuestion!.solutionSteps[si];
    setState(() {
      stepCompleted[si] = true;
      if (stepAnswers[si] == step.correctOption) {
        Future.delayed(const Duration(milliseconds: 400), () { if (mounted) _advanceToNextStep(); });
      }
    });
  }

  void _advanceToNextStep() {
    if (currentSolutionStep < currentQuestion!.solutionSteps.length - 1) {
      setState(() => currentSolutionStep++);
    }
  }

  void _revealNextHint() {
    setState(() {
      switch (currentHintLevel) {
        case HintLevel.none: currentHintLevel = HintLevel.breakdown; break;
        case HintLevel.breakdown: currentHintLevel = HintLevel.statements; break;
        case HintLevel.statements: currentHintLevel = HintLevel.insight; break;
        case HintLevel.insight: currentHintLevel = HintLevel.solution; currentSolutionStep = 0; break;
        case HintLevel.solution: break;
      }
    });
  }

  String _getHintButtonText() {
    switch (currentHintLevel) {
      case HintLevel.none: return "🤔 Need a hint?";
      case HintLevel.breakdown: return "🎯 Identify information";
      case HintLevel.statements: return "💡 Show key insight";
      case HintLevel.insight: return "📝 Show solution";
      case HintLevel.solution: return "✅ In solution";
    }
  }

  bool _canRevealMore() {
    if (currentHintLevel == HintLevel.statements && !statementsChecked) return false;
    return currentHintLevel != HintLevel.solution;
  }

  bool _shouldShowHintButton() {
    if (currentQuestion?.breakdown == null) return false;
    if (currentHintLevel == HintLevel.statements && !statementsChecked) return false;
    return currentHintLevel != HintLevel.solution;
  }

  Widget _buildFloatingHintButton() {
    final isFirst = currentHintLevel == HintLevel.none;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: GestureDetector(
        onTap: _revealNextHint,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isFirst ? const Color(0xFF0D9488) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: isFirst ? null : Border.all(color: const Color(0xFF0D9488)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(
              isFirst ? Icons.help_outline : Icons.arrow_downward,
              color: isFirst ? Colors.white : const Color(0xFF0D9488),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              isFirst ? "Help me understand" : _getHintButtonText(),
              style: TextStyle(
                color: isFirst ? Colors.white : const Color(0xFF0D9488),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(backgroundColor: Color(0xFFF8F9FA), body: Center(child: CircularProgressIndicator(color: Color(0xFF0D9488), strokeWidth: 2)));
    if (quizData == null) return const Scaffold(body: Center(child: Text("Error")));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Stack(
          children: [
            // Main content - constrained to mobile width for web
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildQuestionCard(),
                            const SizedBox(height: 12),
                            if (currentHintLevel.index >= HintLevel.breakdown.index && currentQuestion!.breakdown != null)
                              _buildInfoCard(1, "Problem Breakdown", const Color(0xFF0D9488), _buildBreakdownContent()),
                            if (currentHintLevel.index >= HintLevel.statements.index && currentQuestion!.statements != null)
                              _buildStatementsCard(),
                            if (currentHintLevel.index >= HintLevel.insight.index && currentQuestion!.keyInsight != null)
                              _buildInfoCard(3, "Key Insight", const Color(0xFF374151), _buildBulletList(currentQuestion!.keyInsight!)),
                            if (currentHintLevel == HintLevel.solution) _buildSolutionSection(),
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                    _buildBottomBar(),
                  ],
                ),
              ),
            ),
            // Draggable floating button
            if (_shouldShowHintButton())
              Positioned(
                left: fabPosition.dx,
                top: fabPosition.dy,
                child: Draggable(
                  feedback: _buildDraggableFab(isDragging: true),
                  childWhenDragging: const SizedBox(),
                  onDragEnd: (details) {
                    setState(() {
                      final screenSize = MediaQuery.of(context).size;
                      double newX = details.offset.dx;
                      double newY = details.offset.dy - MediaQuery.of(context).padding.top;
                      newX = newX.clamp(0, screenSize.width - 60);
                      newY = newY.clamp(0, screenSize.height - 150);
                      fabPosition = Offset(newX, newY);
                    });
                  },
                  child: _buildDraggableFab(),
                ),
              ),
            // "Let me solve" popup overlay
            if (showSolvePopup) _buildSolvePopup(),
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableFab({bool isDragging = false}) {
    return Material(
      elevation: isDragging ? 8 : 4,
      borderRadius: BorderRadius.circular(28),
      color: const Color(0xFF0D9488),
      child: InkWell(
        onTap: isDragging ? null : _revealNextHint,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                currentHintLevel == HintLevel.none ? Icons.lightbulb_outline : Icons.arrow_downward,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                currentHintLevel == HintLevel.none ? "Help" : _getHintButtonText().replaceAll(RegExp(r'[^\w\s]'), '').trim(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSolvePopup() {
    final q = currentQuestion!;
    final isCorrect = popupAnswered && popupSelectedOption == q.correctAnswer;
    
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(4)),
                      child: const Text("Try it!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _closeSolvePopup,
                      child: const Icon(Icons.close, color: Color(0xFF6B7280), size: 24),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Question
                LatexText(q.question, style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF374151))),
                const SizedBox(height: 16),
                // Options
                ...List.generate(q.options.length, (i) {
                  final isSelected = popupSelectedOption == i;
                  final isOptCorrect = i == q.correctAnswer;
                  
                  Color textColor = const Color(0xFF4B5563);
                  Color bgColor = const Color(0xFFF9FAFB);
                  Color borderColor = const Color(0xFFE5E7EB);
                  
                  if (popupAnswered && isSelected && !isOptCorrect) {
                    textColor = const Color(0xFFDC2626);
                    bgColor = const Color(0xFFDC2626).withOpacity(0.1);
                    borderColor = const Color(0xFFDC2626);
                  } else if (popupAnswered && isSelected && isOptCorrect) {
                    textColor = const Color(0xFF059669);
                    bgColor = const Color(0xFF059669).withOpacity(0.1);
                    borderColor = const Color(0xFF059669);
                  } else if (isSelected) {
                    textColor = const Color(0xFF7C3AED);
                    bgColor = const Color(0xFF7C3AED).withOpacity(0.1);
                    borderColor = const Color(0xFF7C3AED);
                  }
                  
                  return GestureDetector(
                    onTap: () => _selectPopupOption(i),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Text("${String.fromCharCode(97 + i)}. ", style: TextStyle(fontWeight: FontWeight.w500, color: textColor)),
                          Expanded(child: LatexText(q.options[i], style: TextStyle(fontSize: 14, color: textColor))),
                          if (popupAnswered && isSelected && isOptCorrect) const Icon(Icons.check_circle, color: Color(0xFF059669), size: 18),
                          if (popupAnswered && isSelected && !isOptCorrect) const Icon(Icons.cancel, color: Color(0xFFDC2626), size: 18),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                // Check button or result
                if (!popupAnswered)
                  GestureDetector(
                    onTap: popupSelectedOption != null ? _checkPopupAnswer : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: popupSelectedOption != null ? const Color(0xFF7C3AED) : const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Check Answer",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: popupSelectedOption != null ? Colors.white : const Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (popupAnswered)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isCorrect ? const Color(0xFF059669).withOpacity(0.1) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              isCorrect ? Icons.celebration : Icons.info_outline,
                              color: isCorrect ? const Color(0xFF059669) : const Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isCorrect ? "Correct! Well done! 🎉" : "Not quite. Keep reviewing!",
                                style: TextStyle(
                                  color: isCorrect ? const Color(0xFF059669) : const Color(0xFF92400E),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _closeSolvePopup,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isCorrect ? const Color(0xFF059669) : const Color(0xFF6B7280),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isCorrect ? "Continue" : "Back to Solution",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF0D9488), borderRadius: BorderRadius.circular(4)),
              child: Text("Q${currentQuestion!.id}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(currentQuestion!.topic ?? "", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)))),
            Text("${currentQuestionIndex + 1}/${quizData!.totalQuestions}", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ]),
          const SizedBox(height: 10),
          LatexText(currentQuestion!.question, style: const TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF374151))),
          const SizedBox(height: 10),
          ...List.generate(currentQuestion!.options.length, (i) => _buildOptionRow(i)),
        ],
      ),
    );
  }

  Widget _buildOptionRow(int index) {
    final isSelected = selectedOption == index;
    final isCorrect = index == currentQuestion!.correctAnswer;
    final labels = ['a', 'b', 'c', 'd'];

    Color textColor = const Color(0xFF4B5563);
    Color bgColor = Colors.transparent;

    if (showResult && isSelected && isCorrect) {
      textColor = const Color(0xFF059669); bgColor = const Color(0xFF059669).withOpacity(0.08);
    } else if (showResult && isSelected && !isCorrect) {
      textColor = const Color(0xFFDC2626); bgColor = const Color(0xFFDC2626).withOpacity(0.08);
    } else if (isSelected) {
      textColor = const Color(0xFF0D9488); bgColor = const Color(0xFF0D9488).withOpacity(0.08);
    }

    return GestureDetector(
      onTap: () => _selectOption(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          Text("${labels[index]}. ", style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: textColor)),
          Expanded(child: LatexText(currentQuestion!.options[index], style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: textColor))),
          if (showResult && isSelected && isCorrect) const Icon(Icons.check_circle, color: Color(0xFF059669), size: 16),
          if (showResult && isSelected && !isCorrect) const Icon(Icons.cancel, color: Color(0xFFDC2626), size: 16),
        ]),
      ),
    );
  }

  Widget _buildHelpButton() {
    return GestureDetector(
      onTap: _revealNextHint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D9488).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.3)),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.help_outline, color: Color(0xFF0D9488), size: 20),
          SizedBox(width: 8),
          Text("Help me understand", style: TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ),
    );
  }

  Widget _buildNextHintButton() {
    return GestureDetector(
      onTap: _revealNextHint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_getHintButtonText(), style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_downward, color: Color(0xFF6B7280), size: 16),
        ]),
      ),
    );
  }

  Widget _buildInfoCard(int index, String title, Color color, Widget content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                child: Center(child: Text("$index", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ),
              const SizedBox(width: 12),
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
            ]),
            const SizedBox(height: 8),
            Padding(padding: const EdgeInsets.only(left: 32), child: content),
          ]),
        ),
      ),
    );
  }

  Widget _buildBreakdownContent() {
    final b = currentQuestion!.breakdown!;
    return Column(
      children: b.entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 100, child: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF0D9488)))),
          Expanded(child: LatexText(e.value, style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563), fontStyle: FontStyle.italic))),
        ]),
      )).toList(),
    );
  }

  Widget _buildBulletList(List<String> items) {
    return Column(
      children: items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("• ", style: TextStyle(fontSize: 14, color: Color(0xFF4B5563))),
          Expanded(child: LatexText(item, style: const TextStyle(fontSize: 14, color: Color(0xFF4B5563)))),
        ]),
      )).toList(),
    );
  }

  Widget _buildStatementsCard() {
    final statements = currentQuestion!.statements!;
    final score = _getStatementScore();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(4)),
                child: const Center(child: Text("2", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text("Identify the Information", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF7C3AED)))),
              if (statementsChecked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: score == statements.length ? const Color(0xFF059669) : const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(12)),
                  child: Text("$score/${statements.length}", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ]),
            const SizedBox(height: 6),
            const Text("Categorize each statement:", style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 8),
            ...List.generate(statements.length, (i) => _buildStatementRow(i, statements[i])),
            const SizedBox(height: 8),
            if (!statementsChecked)
              GestureDetector(
                onTap: statementAnswers.length == statements.length ? _checkStatements : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: statementAnswers.length == statements.length ? const Color(0xFF7C3AED) : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text("Check Answers", textAlign: TextAlign.center, style: TextStyle(color: statementAnswers.length == statements.length ? Colors.white : const Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildStatementRow(int index, Statement s) {
    final sel = statementAnswers[index];
    final ok = statementsChecked && sel == s.type;
    final wrong = statementsChecked && sel != null && sel != s.type;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ok ? const Color(0xFF059669).withOpacity(0.1) : wrong ? const Color(0xFFDC2626).withOpacity(0.1) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ok ? const Color(0xFF059669) : wrong ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: LatexText(s.text, style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
            if (statementsChecked) Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? const Color(0xFF059669) : const Color(0xFFDC2626), size: 18),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _buildTypeChip("Given", "given", index, const Color(0xFF0D9488)),
            const SizedBox(width: 8),
            _buildTypeChip("To Find", "calculate", index, const Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            _buildTypeChip("Irrelevant", "irrelevant", index, const Color(0xFF6B7280)),
          ]),
          if (statementsChecked && wrong)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text("Correct: ${_getTypeLabel(s.type)}", style: const TextStyle(fontSize: 12, color: Color(0xFF059669), fontStyle: FontStyle.italic))),
        ]),
      ),
    );
  }

  String _getTypeLabel(String t) => t == "given" ? "Given" : t == "calculate" ? "To Find" : "Irrelevant";

  Widget _buildTypeChip(String label, String type, int idx, Color c) {
    final sel = statementAnswers[idx] == type;
    return GestureDetector(
      onTap: () => _selectStatementType(idx, type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: sel ? c : Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: c)),
        child: Text(label, style: TextStyle(fontSize: 12, color: sel ? Colors.white : c, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildSolutionSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text("THE SOLUTION", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF6B7280), letterSpacing: 0.5)),
      ),
      ...List.generate(currentSolutionStep + 1, (i) {
        if (i < currentQuestion!.solutionSteps.length) return _buildSolutionStepCard(i, currentQuestion!.solutionSteps[i]);
        return const SizedBox();
      }),
    ]);
  }

  Widget _buildSolutionStepCard(int idx, SolutionStep step) {
    final isCompleted = stepCompleted[idx] == true;
    final selectedOpt = stepAnswers[idx];
    final isCorrect = isCompleted && selectedOpt == step.correctOption;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isCompleted ? Border.all(color: isCorrect ? const Color(0xFF059669) : const Color(0xFFF59E0B), width: 2) : null,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: step.isQuiz ? const Color(0xFF7C3AED) : const Color(0xFF0D9488), borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text("${step.step}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(step.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)))),
            if (isCompleted && step.isQuiz) Icon(isCorrect ? Icons.check_circle : Icons.info_outline, color: isCorrect ? const Color(0xFF059669) : const Color(0xFFF59E0B), size: 22),
            if (!step.isQuiz) const Icon(Icons.check_circle, color: Color(0xFF0D9488), size: 20),
          ]),
          const SizedBox(height: 8),
          
          if (step.isQuiz) ...[
            // Intro
            if (step.intro != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                child: LatexText(step.intro!, style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5)),
              ),
            
            // Question
            LatexText(step.question!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF7C3AED))),
            const SizedBox(height: 8),
            
            // Options
            ...List.generate(step.options!.length, (optIdx) {
              final isOptSelected = selectedOpt == optIdx;
              final isOptCorrect = optIdx == step.correctOption;
              
              Color optBg = const Color(0xFFF9FAFB);
              Color optBorder = const Color(0xFFE5E7EB);
              Color optText = const Color(0xFF374151);
              
              if (isCompleted) {
                if (isOptCorrect) {
                  optBg = const Color(0xFF059669).withOpacity(0.1);
                  optBorder = const Color(0xFF059669);
                  optText = const Color(0xFF059669);
                } else if (isOptSelected && !isOptCorrect) {
                  optBg = const Color(0xFFDC2626).withOpacity(0.1);
                  optBorder = const Color(0xFFDC2626);
                  optText = const Color(0xFFDC2626);
                }
              } else if (isOptSelected) {
                optBg = const Color(0xFF7C3AED).withOpacity(0.1);
                optBorder = const Color(0xFF7C3AED);
                optText = const Color(0xFF7C3AED);
              }
              
              return GestureDetector(
                onTap: () => _selectStepOption(idx, optIdx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: optBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: optBorder)),
                  child: Row(children: [
                    Text(String.fromCharCode(65 + optIdx), style: TextStyle(fontWeight: FontWeight.w600, color: optText)),
                    const SizedBox(width: 10),
                    Expanded(child: LatexText(step.options![optIdx], style: TextStyle(fontSize: 14, color: optText))),
                    if (isCompleted && isOptSelected && isOptCorrect) const Icon(Icons.check_circle, color: Color(0xFF059669), size: 18),
                    if (isCompleted && isOptSelected && !isOptCorrect) const Icon(Icons.cancel, color: Color(0xFFDC2626), size: 18),
                  ]),
                ),
              );
            }),
            
            // Check button
            if (!isCompleted && selectedOpt != null)
              GestureDetector(
                onTap: () => _checkStepAnswer(idx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(8)),
                  child: const Text("Check", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            
            // Explanation
            if (isCompleted && !isCorrect && step.explanation != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.lightbulb_outline, color: Color(0xFFF59E0B), size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: LatexText(step.explanation!, style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)))),
                ]),
              ),
            
            // Action buttons row - don't show for correct quiz answers (they auto-advance)
            if (isCompleted && idx == currentSolutionStep && (!step.isQuiz || !isCorrect))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    // "Let me solve" button - only if not already answered AND not on last step
                    if (!showResult && currentSolutionStep < currentQuestion!.solutionSteps.length - 1)
                      Expanded(
                        child: GestureDetector(
                          onTap: _openSolvePopup,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text("Let me solve ✍️", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    if (!showResult && currentSolutionStep < currentQuestion!.solutionSteps.length - 1)
                      const SizedBox(width: 10),
                    // "Next Step" button - show if not answered, or answered wrong
                    if (currentSolutionStep < currentQuestion!.solutionSteps.length - 1 && (!showResult || selectedOption != currentQuestion!.correctAnswer))
                      Expanded(
                        child: GestureDetector(
                          onTap: _advanceToNextStep,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF0D9488)),
                            ),
                            child: const Text("Next Step →", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ] else ...[
            // Non-quiz step
            LatexText(step.content ?? "", style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5)),
            if (idx == currentSolutionStep)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    // "Let me solve" button - only if not already answered AND not on last step
                    if (!showResult && currentSolutionStep < currentQuestion!.solutionSteps.length - 1)
                      Expanded(
                        child: GestureDetector(
                          onTap: _openSolvePopup,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text("Let me solve ✍️", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    if (!showResult && currentSolutionStep < currentQuestion!.solutionSteps.length - 1)
                      const SizedBox(width: 10),
                    // "Next Step" button - show if not answered, or answered wrong
                    if (currentSolutionStep < currentQuestion!.solutionSteps.length - 1 && (!showResult || selectedOption != currentQuestion!.correctAnswer))
                      Expanded(
                        child: GestureDetector(
                          onTap: _advanceToNextStep,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D9488),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text("Next Step →", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2))]),
      child: Row(children: [
        if (currentQuestionIndex > 0) _SmallBtn(Icons.arrow_back, _previousQuestion),
        if (currentQuestionIndex > 0) const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: showResult ? (currentQuestionIndex < quizData!.totalQuestions - 1 ? _nextQuestion : null) : (selectedOption != null ? _checkAnswer : null),
            child: Opacity(
              opacity: (showResult || selectedOption != null) ? 1.0 : 0.5,
              child: Container(
                height: 48,
                decoration: BoxDecoration(color: const Color(0xFF0D9488), borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text(
                  showResult ? (currentQuestionIndex < quizData!.totalQuestions - 1 ? "Next Question →" : "🎉 Complete!") : "Check Answer",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                )),
              ),
            ),
          ),
        ),
        if (currentQuestionIndex < quizData!.totalQuestions - 1 && !showResult) const SizedBox(width: 12),
        if (currentQuestionIndex < quizData!.totalQuestions - 1 && !showResult) _SmallBtn(Icons.arrow_forward, _nextQuestion),
      ]),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SmallBtn(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Icon(icon, color: const Color(0xFF374151), size: 20),
      ),
    );
  }
}
