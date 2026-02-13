#!/usr/bin/env python3
"""Generate a comprehensive 7-page Maternity Leave Policy PDF in French."""

from fpdf import FPDF

class PolicyPDF(FPDF):
    def header(self):
        if self.page_no() > 1:
            self.set_font("Helvetica", "I", 8)
            self.set_text_color(120, 120, 120)
            self.cell(0, 5, "Politique de Congé de Maternité - Organisation de Grande Envergure", align="R")
            self.ln(8)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(120, 120, 120)
        self.cell(0, 10, f"Page {self.page_no()} / {{nb}}", align="C")

    def chapter_title(self, title):
        self.set_font("Helvetica", "B", 14)
        self.set_text_color(0, 51, 102)
        self.cell(0, 10, title, new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(0, 51, 102)
        self.line(self.l_margin, self.get_y(), self.w - self.r_margin, self.get_y())
        self.ln(4)

    def section_title(self, title):
        self.set_font("Helvetica", "B", 11)
        self.set_text_color(0, 70, 130)
        self.cell(0, 8, title, new_x="LMARGIN", new_y="NEXT")
        self.ln(2)

    def body_text(self, text):
        self.set_font("Helvetica", "", 10)
        self.set_text_color(30, 30, 30)
        self.multi_cell(0, 5.5, text)
        self.ln(3)

    def bullet(self, text):
        self.set_font("Helvetica", "", 10)
        self.set_text_color(30, 30, 30)
        x = self.get_x()
        self.cell(8, 5.5, "-")
        self.multi_cell(0, 5.5, text)
        self.ln(1)


pdf = PolicyPDF()
pdf.alias_nb_pages()
pdf.set_auto_page_break(auto=True, margin=20)
pdf.add_page()

# ──────────────────────────────────────────────
# PAGE 1 - Title page + Introduction
# ──────────────────────────────────────────────
pdf.ln(25)
pdf.set_font("Helvetica", "B", 26)
pdf.set_text_color(0, 51, 102)
pdf.cell(0, 15, "Politique de Congé de Maternité", align="C", new_x="LMARGIN", new_y="NEXT")
pdf.ln(5)
pdf.set_font("Helvetica", "", 14)
pdf.set_text_color(80, 80, 80)
pdf.cell(0, 10, "Organisation de Grande Envergure", align="C", new_x="LMARGIN", new_y="NEXT")
pdf.ln(3)
pdf.set_draw_color(0, 51, 102)
pdf.line(60, pdf.get_y(), pdf.w - 60, pdf.get_y())
pdf.ln(8)
pdf.set_font("Helvetica", "I", 10)
pdf.set_text_color(100, 100, 100)
pdf.cell(0, 8, "Version 3.0 - Janvier 2026", align="C", new_x="LMARGIN", new_y="NEXT")
pdf.cell(0, 8, "Direction des Ressources Humaines", align="C", new_x="LMARGIN", new_y="NEXT")
pdf.cell(0, 8, "Document confidentiel - Usage interne uniquement", align="C", new_x="LMARGIN", new_y="NEXT")
pdf.ln(15)

pdf.chapter_title("1. Introduction")
pdf.body_text(
    "Cette politique de congé de maternité a été élaborée afin de fournir des lignes directrices "
    "claires et complètes sur les droits et les responsabilités des employées enceintes au sein "
    "de notre organisation. Elle s'applique à toutes les employées à temps plein et à temps partiel, "
    "sans distinction de poste ou de niveau hiérarchique."
)
pdf.body_text(
    "L'objectif principal de cette politique est de garantir un environnement de travail favorable "
    "à la maternité, tout en assurant la continuité opérationnelle de l'organisation. Cette politique "
    "est conforme à la législation nationale en vigueur et aux conventions collectives applicables."
)
pdf.body_text(
    "Toute modification de cette politique sera communiquée par écrit aux employées concernées et "
    "fera l'objet d'une consultation préalable avec les représentants du personnel."
)

# ──────────────────────────────────────────────
# PAGE 2 - Admissibilité et Durée du Congé
# ──────────────────────────────────────────────
pdf.add_page()
pdf.chapter_title("2. Admissibilité au Congé de Maternité")
pdf.body_text("Pour être admissible au congé de maternité, une employée doit remplir les conditions suivantes :")
pdf.bullet("Être employée par l'organisation depuis au moins 12 mois consécutifs à la date prévue de l'accouchement.")
pdf.bullet("Avoir notifié sa grossesse à son supérieur hiérarchique et au service des ressources humaines par écrit, accompagnée d'un certificat médical, au plus tard à la fin du quatrième mois de grossesse.")
pdf.bullet("Avoir fourni un certificat médical indiquant la date prévue de l'accouchement.")
pdf.bullet("Être à jour dans ses obligations contractuelles envers l'organisation.")
pdf.ln(3)

pdf.body_text(
    "Les employées en période d'essai peuvent bénéficier d'un congé de maternité réduit, "
    "conformément aux dispositions légales minimales applicables. Les employées intérimaires "
    "ou sous contrat à durée déterminée bénéficient des mêmes droits, sous réserve de la "
    "durée restante de leur contrat."
)

pdf.chapter_title("3. Durée du Congé de Maternité")
pdf.body_text("La durée standard du congé de maternité est répartie comme suit :")
pdf.bullet("Congé prénatal : 6 semaines avant la date prévue de l'accouchement (8 semaines en cas de grossesse multiple ou de troisième enfant et plus).")
pdf.bullet("Congé postnatal : 10 semaines après l'accouchement (18 semaines en cas de grossesse multiple).")
pdf.bullet("Congé pathologique supplémentaire : jusqu'à 2 semaines avant l'accouchement et 4 semaines après, sur prescription médicale.")
pdf.ln(2)
pdf.body_text(
    "Le congé prénatal peut être reporté partiellement sur le congé postnatal, dans la limite "
    "de 3 semaines, sous réserve d'un avis médical favorable. Toute hospitalisation de l'enfant "
    "au-delà de 6 semaines après la naissance peut entraîner une prolongation du congé postnatal."
)

# ──────────────────────────────────────────────
# PAGE 3 - Notification et planification du retour
# ──────────────────────────────────────────────
pdf.add_page()
pdf.chapter_title("4. Procédure de Notification")
pdf.body_text(
    "L'employée doit informer son supérieur hiérarchique et le service des ressources humaines "
    "de sa grossesse dès que possible, et au plus tard à la fin du quatrième mois de grossesse. "
    "La notification doit être accompagnée des documents suivants :"
)
pdf.bullet("Un certificat médical attestant de la grossesse et indiquant la date prévue d'accouchement.")
pdf.bullet("Une demande écrite de congé de maternité précisant les dates souhaitées de début et de fin du congé.")
pdf.bullet("Le formulaire interne de demande de congé maternité (formulaire RH-CM-01), disponible sur l'intranet.")
pdf.ln(2)
pdf.body_text(
    "Le service des ressources humaines accusera réception de la notification dans un délai de "
    "5 jours ouvrables et fournira à l'employée un dossier complet comprenant les informations "
    "relatives à ses droits, ses obligations et les démarches administratives à effectuer."
)

pdf.chapter_title("5. Planification du Retour au Travail")
pdf.body_text(
    "L'employée doit informer son supérieur hiérarchique de la date prévue de son retour au "
    "travail au moins 4 semaines avant la fin de son congé de maternité. Cette notification "
    "doit être effectuée par écrit (courriel ou courrier recommandé)."
)
pdf.body_text(
    "Un entretien de pré-reprise pourra être organisé à la demande de l'employée ou de "
    "l'employeur, au cours des 2 dernières semaines du congé. Cet entretien a pour objectif "
    "de préparer les conditions de retour : organisation du poste, aménagements éventuels, "
    "mise à jour sur les évolutions de l'équipe et des projets."
)
pdf.body_text(
    "Si l'employée souhaite prolonger son absence au-delà de la durée du congé de maternité "
    "(par un congé parental, un congé sans solde ou un temps partiel), elle doit en faire la "
    "demande écrite au moins 1 mois avant la date de fin du congé de maternité."
)

# ──────────────────────────────────────────────
# PAGE 4 - Conditions de retour au travail
# ──────────────────────────────────────────────
pdf.add_page()
pdf.chapter_title("6. Conditions de Retour au Travail")

pdf.section_title("6.1 Réaffectation au poste d'origine")
pdf.body_text(
    "À son retour de congé de maternité, l'employée retrouvera son poste d'origine, avec les "
    "mêmes conditions de travail et de rémunération. Si le poste d'origine n'est plus disponible "
    "en raison de restructurations ou de réorganisations significatives survenues pendant le congé, "
    "l'employée se verra proposer un poste équivalent, de même niveau hiérarchique et de rémunération "
    "au moins égale."
)

pdf.section_title("6.2 Maintien de l'ancienneté et des avantages")
pdf.body_text(
    "La totalité de la période de congé de maternité est comptabilisée comme du temps de service "
    "effectif pour le calcul de l'ancienneté, des droits à congés payés et de la retraite. "
    "L'employée conserve le bénéfice de toutes les augmentations générales de salaire et des "
    "avantages collectifs accordés pendant son absence."
)

pdf.section_title("6.3 Aménagement du temps de travail")
pdf.body_text(
    "Pendant les 6 premiers mois suivant son retour, l'employée pourra bénéficier, sur demande, "
    "d'un aménagement de ses horaires de travail, notamment :"
)
pdf.bullet("Réduction temporaire du temps de travail (passage à 80 % avec maintien de salaire à 100 % pendant le premier mois).")
pdf.bullet("Horaires flexibles pour faciliter la conciliation vie professionnelle / vie familiale.")
pdf.bullet("Possibilité de télétravail partiel (jusqu'à 2 jours par semaine), sous réserve de la compatibilité avec les fonctions occupées.")
pdf.bullet("Pause d'allaitement : 1 heure par jour fractionnée en deux périodes de 30 minutes, pendant les 12 premiers mois suivant la naissance.")

pdf.section_title("6.4 Visite médicale de reprise")
pdf.body_text(
    "Une visite médicale de reprise avec le médecin du travail est obligatoire dans les 8 jours "
    "suivant le retour de l'employée. Cette visite vise à s'assurer de l'aptitude au poste de "
    "travail et à envisager, le cas échéant, des adaptations du poste."
)

# ──────────────────────────────────────────────
# PAGE 5 - Protection de l'emploi & Droits et obligations
# ──────────────────────────────────────────────
pdf.add_page()
pdf.chapter_title("7. Protection de l'Emploi")
pdf.body_text(
    "L'organisation garantit que l'employée ne subira aucune discrimination ou rétrogradation "
    "en raison de sa grossesse ou de son congé de maternité. Cette protection couvre :"
)
pdf.bullet("L'interdiction de licencier une employée pendant la grossesse et le congé de maternité, sauf faute grave non liée à la grossesse ou impossibilité de maintenir le contrat pour un motif étranger à la maternité.")
pdf.bullet("L'interdiction de toute modification unilatérale du contrat de travail pendant cette période.")
pdf.bullet("La protection contre toute forme de harcèlement ou de pression liée à la grossesse ou au congé de maternité.")
pdf.bullet("Le maintien du droit à la formation professionnelle et à l'évolution de carrière.")
pdf.ln(2)
pdf.body_text(
    "Toute violation de cette politique sera traitée avec la plus grande rigueur et pourra faire "
    "l'objet de sanctions disciplinaires pouvant aller jusqu'au licenciement du responsable. "
    "L'employée victime de discrimination pourra saisir le comité d'éthique, les représentants "
    "du personnel ou les instances judiciaires compétentes."
)

pdf.chapter_title("8. Droits et Obligations de l'Employée et de l'Employeur")
pdf.section_title("8.1 Droits de l'employée")
pdf.bullet("Bénéficier de l'intégralité de son congé de maternité sans perte de rémunération (maintien du salaire à 100 % par l'employeur, déduction faite des indemnités journalières de la sécurité sociale).")
pdf.bullet("Recevoir toutes les informations relatives à ses droits et obligations avant le début du congé.")
pdf.bullet("Demander un entretien de pré-reprise et bénéficier d'un accompagnement au retour.")
pdf.bullet("Refuser tout travail présentant un risque pour sa santé ou celle de l'enfant à naître.")

pdf.section_title("8.2 Obligations de l'employée")
pdf.bullet("Notifier sa grossesse dans les délais prescrits et fournir les certificats médicaux requis.")
pdf.bullet("Informer l'employeur de la date prévue de retour au moins 4 semaines à l'avance.")
pdf.bullet("Se soumettre à la visite médicale de reprise dans les 8 jours suivant son retour.")

pdf.section_title("8.3 Obligations de l'employeur")
pdf.bullet("Maintenir le poste ou proposer un poste équivalent au retour de congé.")
pdf.bullet("Assurer la continuité de la couverture santé et des avantages sociaux pendant le congé.")
pdf.bullet("Organiser la visite médicale de reprise et les aménagements nécessaires.")

# ──────────────────────────────────────────────
# PAGE 6 - Congé de paternité, congé parental & Rémunération
# ──────────────────────────────────────────────
pdf.add_page()
pdf.chapter_title("9. Congé de Paternité et Congé Parental")
pdf.body_text(
    "En plus du congé de maternité, l'organisation offre également des congés de paternité "
    "et des congés parentaux. Les détails de ces congés sont décrits dans la politique de congé "
    "parental (document RH-CP-02). Les points essentiels sont :"
)
pdf.bullet("Congé de paternité : 25 jours calendaires (32 jours en cas de naissances multiples), dont 4 jours obligatoires immédiatement après la naissance.")
pdf.bullet("Congé parental d'éducation : jusqu'à 3 ans, accessible aux deux parents, à temps plein ou à temps partiel.")
pdf.bullet("Congé d'adoption : mêmes droits que le congé de maternité, adaptés à la procédure d'adoption.")
pdf.ln(2)

pdf.chapter_title("10. Rémunération et Avantages pendant le Congé")
pdf.section_title("10.1 Maintien du salaire")
pdf.body_text(
    "Pendant la durée du congé de maternité légal, l'employée bénéficie du maintien de sa "
    "rémunération à 100 %, sous déduction des indemnités journalières versées par la sécurité "
    "sociale. Ce maintien couvre le salaire de base ainsi que les primes récurrentes."
)
pdf.section_title("10.2 Avantages sociaux")
pdf.body_text(
    "L'ensemble des avantages sociaux (mutuelle, prévoyance, titres restaurant, participation "
    "aux bénéfices) sont maintenus pendant la durée du congé de maternité. Les cotisations "
    "salariales restent à la charge de l'employée selon les modalités habituelles."
)
pdf.section_title("10.3 Épargne salariale et intéressement")
pdf.body_text(
    "L'absence pour congé de maternité n'affecte pas le droit à la participation et à "
    "l'intéressement. Le calcul de ces droits est effectué comme si l'employée avait été "
    "présente pendant toute la période."
)

# ──────────────────────────────────────────────
# PAGE 7 - Accompagnement, contacts RH
# ──────────────────────────────────────────────
pdf.add_page()
pdf.chapter_title("11. Accompagnement et Soutien")
pdf.body_text(
    "L'organisation met à disposition des employées un programme complet d'accompagnement "
    "avant, pendant et après le congé de maternité :"
)
pdf.bullet("Programme de mentorat : une collègue ayant vécu une expérience similaire pourra être désignée comme marraine pour accompagner l'employée tout au long du processus.")
pdf.bullet("Accès à un service de conseil psychologique confidentiel et gratuit (programme d'aide aux employés - PAE), joignable 24 h/24 au 0 800 XXX XXX.")
pdf.bullet("Sessions d'information trimestrielles sur les droits liés à la parentalité, organisées par le service RH.")
pdf.bullet("Guide pratique 'Devenir parent dans l'entreprise', disponible en version papier et numérique sur l'intranet.")
pdf.ln(3)

pdf.chapter_title("12. Procédures Internes et Formulaires")
pdf.body_text("Les formulaires suivants sont disponibles sur l'intranet RH (rubrique Parentalite) :")
pdf.bullet("RH-CM-01 : Demande de congé de maternité.")
pdf.bullet("RH-CM-02 : Notification de date de retour.")
pdf.bullet("RH-CM-03 : Demande d'aménagement des horaires au retour.")
pdf.bullet("RH-CM-04 : Demande de congé parental (à remettre au moins 1 mois avant la fin du congé maternité).")
pdf.ln(3)

pdf.chapter_title("13. Contacts RH")
pdf.body_text("Pour toute question relative au congé de maternité, les employées peuvent contacter :")
pdf.ln(2)
pdf.set_font("Helvetica", "", 10)
contacts = [
    ("Service des Ressources Humaines - Équipe Parentalité", "parentalite@organisation.com", "+33 1 XX XX XX XX"),
    ("Responsable RH de proximité", "Voir l'annuaire interne pour votre site", ""),
    ("Médecine du travail", "medecinetravail@organisation.com", "+33 1 XX XX XX XX"),
    ("Programme d'aide aux employés (PAE)", "pae@organisation.com", "0 800 XXX XXX (24 h/24)"),
]
for name, email, phone in contacts:
    pdf.set_font("Helvetica", "B", 10)
    pdf.cell(0, 6, name, new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    if email:
        pdf.cell(0, 5, f"   Courriel : {email}", new_x="LMARGIN", new_y="NEXT")
    if phone:
        pdf.cell(0, 5, f"   Téléphone : {phone}", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)

pdf.ln(6)
pdf.set_draw_color(0, 51, 102)
pdf.line(pdf.l_margin, pdf.get_y(), pdf.w - pdf.r_margin, pdf.get_y())
pdf.ln(4)
pdf.set_font("Helvetica", "I", 9)
pdf.set_text_color(100, 100, 100)
pdf.multi_cell(0, 5,
    "Ce document est la propriété de l'Organisation de Grande Envergure. Il ne peut être reproduit, "
    "distribué ou communiqué à des tiers sans l'autorisation préalable écrite de la Direction des "
    "Ressources Humaines. Dernière mise à jour : Janvier 2026."
)

# Save
output_path = "/workspaces/foundryiq-sharepoint/Politique de Congé de Maternité.pdf"
pdf.output(output_path)
print(f"PDF generated: {output_path}")
print(f"Pages: {pdf.pages_count}")
