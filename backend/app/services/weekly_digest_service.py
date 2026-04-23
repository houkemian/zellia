import logging
import smtplib
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from email.message import EmailMessage
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.models import FamilyLink, User
from app.routers.reports import build_clinical_summary

logger = logging.getLogger(__name__)
TEMPLATES_DIR = Path(__file__).resolve().parents[2] / "templates"
jinja_env = Environment(
    loader=FileSystemLoader(str(TEMPLATES_DIR)),
    autoescape=select_autoescape(["html", "xml"]),
)


def _send_html_email(to_email: str, subject: str, html_body: str) -> None:
    if not settings.smtp_host or not settings.smtp_from_email:
        logger.warning("SMTP not configured, skip weekly digest for %s", to_email)
        return

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = settings.smtp_from_email
    message["To"] = to_email
    message.set_content("请使用支持 HTML 的邮件客户端查看周报。")
    message.add_alternative(html_body, subtype="html")

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=20) as smtp:
        if settings.smtp_use_tls:
            smtp.starttls()
        if settings.smtp_username and settings.smtp_password:
            smtp.login(settings.smtp_username, settings.smtp_password)
        smtp.send_message(message)


def _render_weekly_digest_html(
    caregiver_name: str,
    elder_name: str,
    summary: dict,
) -> str:
    template = jinja_env.get_template("weekly_digest.html")
    med = summary.get("medication_adherence", {})
    bp = summary.get("blood_pressure_summary", {})
    period = summary.get("period", {})
    return template.render(
        caregiver_name=caregiver_name,
        elder_name=elder_name,
        report_date=datetime.now().strftime("%Y-%m-%d"),
        period_start=period.get("start_date", ""),
        period_end=period.get("end_date", ""),
        adherence_percent=f"{float(med.get('percent', 0)):.1f}",
        taken_count=med.get("taken_count", 0),
        total_tasks=med.get("total_tasks", 0),
        avg_systolic=bp.get("average_systolic"),
        avg_diastolic=bp.get("average_diastolic"),
        avg_heart_rate=bp.get("average_heart_rate"),
        abnormal_count=bp.get("abnormal_count", 0),
    )


def send_weekly_digests(db: Session) -> None:
    links = db.execute(
        select(FamilyLink).where(
            FamilyLink.status == "APPROVED",
            FamilyLink.receive_weekly_report.is_(True),
        )
    ).scalars().all()
    if not links:
        return

    jobs: list[tuple[str, str, str]] = []
    for link in links:
        elder = db.get(User, link.elder_id)
        caregiver = db.get(User, link.caregiver_id)
        if elder is None or caregiver is None:
            continue
        if "@" not in caregiver.username:
            logger.info("Skip weekly digest: caregiver username is not email (%s)", caregiver.username)
            continue
        summary = build_clinical_summary(db, elder.id, days=7)
        html = _render_weekly_digest_html(
            caregiver_name=caregiver.username,
            elder_name=(link.elder_alias or elder.username),
            summary=summary,
        )
        subject = f"Zellia 本周健康周报 - {link.elder_alias or elder.username}"
        jobs.append((caregiver.username, subject, html))

    if not jobs:
        return

    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = [
            pool.submit(_send_html_email, to_email=email, subject=subject, html_body=html)
            for email, subject, html in jobs
        ]
        for fut in as_completed(futures):
            try:
                fut.result()
            except Exception as exc:
                # isolate single failure so batch keeps running
                logger.exception("Weekly digest send failed for one recipient: %s", exc)
