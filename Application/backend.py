from fastapi import FastAPI, HTTPException, Depends, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import create_engine, Column, Integer, String, Float, Text, Boolean, DateTime, Date
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from datetime import datetime, timedelta
from typing import Optional, List
import jwt
from passlib.context import CryptContext
import os
from pydantic import BaseModel
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# Database setup
DATABASE_URL = "sqlite:///./job_search.db"
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# JWT setup
SECRET_KEY = "your-secret-key-change-this"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Security
security = HTTPBearer()

# ---------- MODELS ----------
class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    full_name = Column(String)
    date_of_birth = Column(Date, nullable=True)
    location = Column(String)
    graduation_date = Column(Date, nullable=True)
    graduation_institution = Column(String)
    transportation_mode = Column(String)
    resume_url = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

class Job(Base):
    __tablename__ = "jobs"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String)
    company = Column(String)
    location = Column(String)
    salary_min = Column(Float, nullable=True)
    salary_max = Column(Float, nullable=True)
    description = Column(Text)
    requirements = Column(Text)
    job_type = Column(String)
    category = Column(String)
    is_remote = Column(Boolean, default=False)
    posted_date = Column(DateTime, default=datetime.utcnow)

class JobApplication(Base):
    __tablename__ = "applications"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer)
    job_id = Column(Integer)
    status = Column(String, default="pending")
    applied_at = Column(DateTime, default=datetime.utcnow)

Base.metadata.create_all(bind=engine)

# ---------- PYDANTIC SCHEMAS ----------
class UserCreate(BaseModel):
    email: str
    password: str
    full_name: str
    date_of_birth: Optional[str] = None
    location: str
    graduation_date: Optional[str] = None
    graduation_institution: str
    transportation_mode: str

class UserResponse(BaseModel):
    id: int
    email: str
    full_name: str
    location: str

class LoginRequest(BaseModel):
    email: str
    password: str

class JobCreate(BaseModel):
    title: str
    company: str
    location: str
    salary_min: Optional[float] = None
    salary_max: Optional[float] = None
    description: str
    requirements: str
    job_type: str
    category: str
    is_remote: bool = False

class JobResponse(BaseModel):
    id: int
    title: str
    company: str
    location: str
    salary_min: Optional[float]
    salary_max: Optional[float]
    description: str
    requirements: str
    job_type: str
    category: str
    is_remote: bool
    posted_date: datetime

class ApplicationCreate(BaseModel):
    job_id: int

# ---------- EMAIL SERVICE ----------
class EmailService:
    @staticmethod
    def send_application_confirmation(to_email: str, job_title: str, company: str):
        """Send confirmation email (simplified - print to console)"""
        print(f"\n📧 Email sent to: {to_email}")
        print(f"Subject: Application Confirmation - {job_title}")
        print(f"Body: Thank you for applying to {job_title} at {company}!")
        print("We will review your application and contact you soon.\n")

# ---------- APP SETUP ----------
app = FastAPI(title="Job Search API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ---------- AUTH FUNCTIONS ----------
def verify_password(plain_password, hashed_password):
    # Truncate password to 72 bytes for bcrypt compatibility
    if isinstance(plain_password, str):
        plain_password = plain_password.encode('utf-8')[:72].decode('utf-8', errors='ignore')
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    # Truncate password to 72 bytes for bcrypt compatibility
    if isinstance(password, str):
        password = password.encode('utf-8')[:72].decode('utf-8', errors='ignore')
    return pwd_context.hash(password)

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def get_current_user_email(credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        token = credentials.credentials
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise HTTPException(status_code=401, detail="Invalid authentication credentials")
        return email
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.JWTError:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

def get_current_user(email: str = Depends(get_current_user_email), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == email).first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return user

# ---------- API ENDPOINTS ----------
@app.post("/auth/signup")
async def signup(
    email: str = Form(...),
    password: str = Form(...),
    full_name: str = Form(...),
    date_of_birth: Optional[str] = Form(None),
    location: str = Form(...),
    graduation_date: Optional[str] = Form(None),
    graduation_institution: str = Form(...),
    transportation_mode: str = Form(...),
    resume: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db)
):
    # Check if user exists
    db_user = db.query(User).filter(User.email == email).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Email already registered")
    
    # Create user
    hashed_password = get_password_hash(password)
    
    # Parse dates
    dob = datetime.strptime(date_of_birth, "%Y-%m-%d").date() if date_of_birth else None
    grad_date = datetime.strptime(graduation_date, "%Y-%m-%d").date() if graduation_date else None
    
    db_user = User(
        email=email,
        hashed_password=hashed_password,
        full_name=full_name,
        date_of_birth=dob,
        location=location,
        graduation_date=grad_date,
        graduation_institution=graduation_institution,
        transportation_mode=transportation_mode,
        resume_url=f"/resumes/{email}_resume.pdf" if resume else None
    )
    
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    
    # Create token
    access_token = create_access_token(data={"sub": email})
    
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user": {
            "id": db_user.id,
            "email": db_user.email,
            "full_name": db_user.full_name,
            "location": db_user.location
        }
    }

@app.post("/auth/login")
async def login(request: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == request.email).first()
    if not user or not verify_password(request.password, user.hashed_password):
        raise HTTPException(status_code=400, detail="Invalid credentials")
    
    access_token = create_access_token(data={"sub": user.email})
    
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "email": user.email,
            "full_name": user.full_name,
            "location": user.location,
            "date_of_birth": user.date_of_birth.isoformat() if user.date_of_birth else None,
            "graduation_date": user.graduation_date.isoformat() if user.graduation_date else None,
            "graduation_institution": user.graduation_institution,
            "transportation_mode": user.transportation_mode
        }
    }

@app.get("/jobs/")
async def get_jobs(
    title: Optional[str] = None,
    location: Optional[str] = None,
    category: Optional[str] = None,
    db: Session = Depends(get_db)
):
    query = db.query(Job)
    
    if title:
        query = query.filter(Job.title.contains(title))
    if location:
        query = query.filter(Job.location.contains(location))
    if category and category != "Any":
        query = query.filter(Job.category == category)
    
    jobs = query.all()
    print(f"Found {len(jobs)} jobs in database")
    
    # If no jobs in DB, add sample data (85+ jobs covering all fields)
    if not jobs:
        sample_jobs = [
            # IT & Software Development (20 jobs)
            Job(title="Flutter Developer", company="Tech Corp", location="New York, NY", salary_min=80000, salary_max=120000, description="We are looking for a skilled Flutter developer to build cross-platform mobile applications.", requirements="3+ years experience, Dart knowledge, Flutter framework", job_type="Full-time", category="IT", is_remote=True),
            Job(title="Data Analyst", company="Data Insights", location="San Francisco, CA", salary_min=70000, salary_max=110000, description="Analyze business data and provide insights for decision making.", requirements="SQL, Python, Statistics knowledge", job_type="Contract", category="IT", is_remote=False),
            Job(title="Senior Python Developer", company="CodeCraft Inc", location="Austin, TX", salary_min=95000, salary_max=140000, description="Develop scalable backend systems using Python and Django.", requirements="5+ years Python, Django, REST APIs", job_type="Full-time", category="IT", is_remote=True),
            Job(title="Product Manager", company="Innovation Labs", location="Seattle, WA", salary_min=100000, salary_max=150000, description="Define product roadmap and work with engineering teams.", requirements="7+ years product management experience", job_type="Full-time", category="IT", is_remote=False),
            Job(title="UX Designer", company="Design Studio", location="Los Angeles, CA", salary_min=70000, salary_max=95000, description="Create beautiful and intuitive user interfaces.", requirements="Portfolio, Figma, UI/UX principles", job_type="Full-time", category="IT", is_remote=True),
            Job(title="DevOps Engineer", company="Cloud Solutions", location="Remote", salary_min=90000, salary_max=130000, description="Manage cloud infrastructure and CI/CD pipelines.", requirements="AWS/Azure, Docker, Kubernetes, Terraform", job_type="Full-time", category="IT", is_remote=True),
            Job(title="React Developer", company="WebDev Co", location="Denver, CO", salary_min=85000, salary_max=115000, description="Build modern web applications using React and TypeScript.", requirements="React, JavaScript/TypeScript, Redux", job_type="Full-time", category="IT", is_remote=True),
            Job(title="Mobile App Tester", company="QA Masters", location="Remote", salary_min=50000, salary_max=70000, description="Test mobile applications across different devices.", requirements="Testing experience, attention to detail", job_type="Contract", category="IT", is_remote=True),
            Job(title="Data Scientist", company="AI Innovations", location="San Francisco, CA", salary_min=110000, salary_max=160000, description="Build machine learning models and analyze complex datasets.", requirements="Python, ML frameworks, Statistics PhD preferred", job_type="Full-time", category="IT", is_remote=False),
            Job(title="Backend Engineer", company="StartupXYZ", location="New York, NY", salary_min=95000, salary_max=135000, description="Design and implement scalable backend services.", requirements="Node.js or Python, databases, microservices", job_type="Full-time", category="IT", is_remote=False),
            Job(title="Java Developer", company="Enterprise Solutions", location="Atlanta, GA", salary_min=90000, salary_max=125000, description="Develop enterprise applications using Java and Spring.", requirements="Java, Spring Boot, microservices architecture", job_type="Full-time", category="IT", is_remote=False),
            Job(title="iOS Developer", company="Mobile First", location="San Jose, CA", salary_min=95000, salary_max=135000, description="Build native iOS applications using Swift.", requirements="Swift, iOS SDK, UIKit, SwiftUI", job_type="Full-time", category="IT", is_remote=False),
            Job(title="Full Stack Developer", company="Tech Startup", location="Remote", salary_min=85000, salary_max=120000, description="Build end-to-end web applications.", requirements="React, Node.js, MongoDB, REST APIs", job_type="Full-time", category="IT", is_remote=True),
            Job(title="AI/ML Engineer", company="Deep Learning Co", location="Boston, MA", salary_min=120000, salary_max=170000, description="Develop and deploy machine learning models.", requirements="TensorFlow, PyTorch, Deep Learning, Python", job_type="Full-time", category="IT", is_remote=False),
            Job(title="Cybersecurity Analyst", company="SecureNet", location="Remote", salary_min=85000, salary_max=115000, description="Monitor and protect systems from security threats.", requirements="Security certifications, penetration testing", job_type="Full-time", category="IT", is_remote=True),
            Job(title="Database Administrator", company="DataSafe Inc", location="Chicago, IL", salary_min=75000, salary_max=105000, description="Manage and optimize database systems.", requirements="SQL Server, PostgreSQL, performance tuning", job_type="Full-time", category="IT", is_remote=False),
            Job(title="Cloud Architect", company="CloudTech", location="Remote", salary_min=130000, salary_max=180000, description="Design cloud infrastructure and migration strategies.", requirements="AWS/Azure/GCP certified, 7+ years experience", job_type="Full-time", category="IT", is_remote=True),
            Job(title="Software Tester", company="QA Solutions", location="Austin, TX", salary_min=55000, salary_max=80000, description="Perform automated and manual testing.", requirements="Selenium, test automation, Agile methodology", job_type="Full-time", category="IT", is_remote=False),
            Job(title="Technical Writer", company="DocTech", location="Remote", salary_min=60000, salary_max=85000, description="Create technical documentation and user guides.", requirements="Technical writing, API documentation", job_type="Full-time", category="IT", is_remote=True),
            Job(title="Network Engineer", company="NetWorks LLC", location="Houston, TX", salary_min=70000, salary_max=100000, description="Design and maintain network infrastructure.", requirements="Cisco, networking protocols, troubleshooting", job_type="Full-time", category="IT", is_remote=False),
            
            # Marketing & Sales (15 jobs)
            Job(title="Marketing Manager", company="Marketing Pro", location="Remote", salary_min=60000, salary_max=90000, description="Lead our marketing team and develop strategies to grow our brand.", requirements="5+ years experience in digital marketing", job_type="Full-time", category="Marketing", is_remote=True),
            Job(title="Sales Representative", company="SalesPro Corp", location="Chicago, IL", salary_min=50000, salary_max=75000, description="Drive sales and build relationships with clients.", requirements="2+ years sales experience, excellent communication", job_type="Full-time", category="Marketing", is_remote=False),
            Job(title="Content Writer", company="MediaWorks", location="Remote", salary_min=45000, salary_max=65000, description="Create engaging content for various platforms.", requirements="Strong writing skills, SEO knowledge", job_type="Part-time", category="Marketing", is_remote=True),
            Job(title="Graphic Designer", company="Creative Agency", location="Miami, FL", salary_min=55000, salary_max=80000, description="Design visual content for marketing campaigns.", requirements="Adobe Creative Suite, portfolio required", job_type="Full-time", category="Marketing", is_remote=False),
            Job(title="SEO Specialist", company="Digital Growth", location="Remote", salary_min=55000, salary_max=80000, description="Optimize websites for search engines and drive organic traffic.", requirements="SEO tools, Google Analytics, content strategy", job_type="Full-time", category="Marketing", is_remote=True),
            Job(title="Social Media Manager", company="Brand Builders", location="Remote", salary_min=50000, salary_max=75000, description="Manage social media accounts and create engaging content.", requirements="Social media experience, content creation skills", job_type="Full-time", category="Marketing", is_remote=True),
            Job(title="Digital Marketing Specialist", company="AdTech Solutions", location="Los Angeles, CA", salary_min=60000, salary_max=85000, description="Plan and execute digital marketing campaigns.", requirements="Google Ads, Facebook Ads, analytics", job_type="Full-time", category="Marketing", is_remote=False),
            Job(title="Brand Manager", company="Consumer Goods Co", location="New York, NY", salary_min=80000, salary_max=110000, description="Develop and maintain brand identity.", requirements="Brand strategy, market research, 5+ years", job_type="Full-time", category="Marketing", is_remote=False),
            Job(title="Email Marketing Specialist", company="EmailPro", location="Remote", salary_min=50000, salary_max=70000, description="Create and manage email marketing campaigns.", requirements="Mailchimp, A/B testing, copywriting", job_type="Full-time", category="Marketing", is_remote=True),
            Job(title="Public Relations Manager", company="PR Experts", location="Washington DC", salary_min=70000, salary_max=95000, description="Manage media relations and company reputation.", requirements="PR experience, media contacts, crisis management", job_type="Full-time", category="Marketing", is_remote=False),
            Job(title="Video Editor", company="Media Production", location="Remote", salary_min=55000, salary_max=80000, description="Edit video content for various platforms.", requirements="Adobe Premiere, Final Cut Pro, creativity", job_type="Contract", category="Marketing", is_remote=True),
            Job(title="Copywriter", company="Ad Agency", location="Chicago, IL", salary_min=55000, salary_max=75000, description="Write compelling copy for advertisements.", requirements="Creative writing, advertising experience", job_type="Full-time", category="Marketing", is_remote=False),
            Job(title="Marketing Analyst", company="Analytics Co", location="Remote", salary_min=65000, salary_max=90000, description="Analyze marketing data and campaign performance.", requirements="Data analysis, Excel, marketing metrics", job_type="Full-time", category="Marketing", is_remote=True),
            Job(title="Event Coordinator", company="Events Plus", location="Las Vegas, NV", salary_min=45000, salary_max=65000, description="Plan and execute corporate events.", requirements="Event planning, organization skills", job_type="Full-time", category="Marketing", is_remote=False),
            Job(title="Influencer Marketing Manager", company="Social Reach", location="Remote", salary_min=70000, salary_max=95000, description="Manage influencer partnerships and campaigns.", requirements="Influencer marketing, negotiation skills", job_type="Full-time", category="Marketing", is_remote=True),
            
            # Engineering (15 jobs)
            Job(title="Mechanical Engineer", company="AutoTech Inc", location="Detroit, MI", salary_min=75000, salary_max=105000, description="Design mechanical systems for automotive products.", requirements="CAD, SolidWorks, 3+ years experience", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Electrical Engineer", company="PowerGrid Solutions", location="Houston, TX", salary_min=80000, salary_max=110000, description="Design electrical systems and circuits.", requirements="Circuit design, MATLAB, power systems", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Civil Engineer", company="Construction Pros", location="Phoenix, AZ", salary_min=70000, salary_max=95000, description="Design infrastructure and construction projects.", requirements="AutoCAD, structural analysis, PE license", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Chemical Engineer", company="ChemTech Industries", location="Newark, NJ", salary_min=85000, salary_max=115000, description="Develop chemical processes and products.", requirements="Process engineering, ChemCAD, safety protocols", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Biomedical Engineer", company="MedDevice Corp", location="Boston, MA", salary_min=80000, salary_max=110000, description="Design medical devices and equipment.", requirements="Medical devices, FDA regulations, CAD", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Aerospace Engineer", company="AeroSpace Systems", location="Seattle, WA", salary_min=95000, salary_max=135000, description="Design aircraft and spacecraft systems.", requirements="Aerodynamics, CATIA, systems engineering", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Industrial Engineer", company="Manufacturing Co", location="Cleveland, OH", salary_min=70000, salary_max=95000, description="Optimize production processes and efficiency.", requirements="Lean manufacturing, Six Sigma, process improvement", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Quality Engineer", company="QualityFirst", location="San Diego, CA", salary_min=75000, salary_max=100000, description="Ensure product quality and compliance.", requirements="Quality management, ISO standards, inspection", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Process Engineer", company="Tech Manufacturing", location="Austin, TX", salary_min=80000, salary_max=110000, description="Improve manufacturing processes.", requirements="Process optimization, lean principles, data analysis", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Environmental Engineer", company="EcoSolutions", location="Portland, OR", salary_min=70000, salary_max=95000, description="Develop solutions for environmental issues.", requirements="Environmental science, regulations, water treatment", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Structural Engineer", company="BuildRight", location="Miami, FL", salary_min=85000, salary_max=115000, description="Design structural systems for buildings.", requirements="Structural analysis, steel/concrete design, PE license", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Systems Engineer", company="Defense Systems", location="Arlington, VA", salary_min=95000, salary_max=130000, description="Design complex system architectures.", requirements="Systems engineering, requirements analysis, DoD clearance", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Manufacturing Engineer", company="Auto Parts Inc", location="Detroit, MI", salary_min=75000, salary_max=100000, description="Design and improve manufacturing processes.", requirements="Manufacturing systems, automation, CAD", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Petroleum Engineer", company="Energy Corp", location="Dallas, TX", salary_min=90000, salary_max=130000, description="Design oil and gas extraction systems.", requirements="Reservoir engineering, drilling operations", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Materials Engineer", company="Advanced Materials", location="Pittsburgh, PA", salary_min=80000, salary_max=110000, description="Research and develop new materials.", requirements="Materials science, testing, R&D experience", job_type="Full-time", category="Other", is_remote=False),
            
            # Finance & Business (15 jobs)
            Job(title="Financial Analyst", company="FinTech Solutions", location="Boston, MA", salary_min=75000, salary_max=105000, description="Analyze financial data and create reports.", requirements="Finance degree, Excel, financial modeling", job_type="Full-time", category="Finance", is_remote=False),
            Job(title="Accountant", company="Accounting Firm", location="New York, NY", salary_min=60000, salary_max=85000, description="Manage financial records and prepare reports.", requirements="CPA, accounting software, 3+ years", job_type="Full-time", category="Finance", is_remote=False),
            Job(title="Investment Banker", company="Goldman & Associates", location="New York, NY", salary_min=120000, salary_max=200000, description="Provide financial advisory services.", requirements="Finance degree, MBA preferred, deal experience", job_type="Full-time", category="Finance", is_remote=False),
            Job(title="Tax Advisor", company="Tax Experts", location="Chicago, IL", salary_min=70000, salary_max=95000, description="Provide tax planning and compliance services.", requirements="CPA, tax law, client management", job_type="Full-time", category="Finance", is_remote=False),
            Job(title="Auditor", company="Audit Solutions", location="Atlanta, GA", salary_min=65000, salary_max=90000, description="Conduct financial audits and reviews.", requirements="CPA, auditing standards, analytical skills", job_type="Full-time", category="Finance", is_remote=False),
            Job(title="Business Analyst", company="Consulting Group", location="Washington DC", salary_min=75000, salary_max=100000, description="Analyze business processes and recommend improvements.", requirements="Business analysis, requirements gathering, Agile", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Management Consultant", company="Strategy Consultants", location="San Francisco, CA", salary_min=100000, salary_max=150000, description="Advise businesses on strategy and operations.", requirements="MBA, consulting experience, problem-solving", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Operations Manager", company="Logistics Co", location="Memphis, TN", salary_min=70000, salary_max=95000, description="Oversee daily operations and logistics.", requirements="Operations management, process improvement", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Risk Analyst", company="Insurance Corp", location="Hartford, CT", salary_min=70000, salary_max=95000, description="Assess and manage business risks.", requirements="Risk analysis, statistics, financial modeling", job_type="Full-time", category="Finance", is_remote=False),
            Job(title="Portfolio Manager", company="Investment Firm", location="New York, NY", salary_min=110000, salary_max=160000, description="Manage investment portfolios.", requirements="CFA, portfolio management, market analysis", job_type="Full-time", category="Finance", is_remote=False),
            Job(title="Financial Controller", company="Manufacturing Corp", location="Cleveland, OH", salary_min=90000, salary_max=125000, description="Oversee financial reporting and controls.", requirements="CPA, controller experience, leadership", job_type="Full-time", category="Finance", is_remote=False),
            Job(title="Budget Analyst", company="Government Agency", location="Washington DC", salary_min=65000, salary_max=85000, description="Analyze and prepare budget reports.", requirements="Budget analysis, Excel, government experience", job_type="Full-time", category="Finance", is_remote=False),
            Job(title="Credit Analyst", company="Banking Corp", location="Charlotte, NC", salary_min=60000, salary_max=80000, description="Evaluate creditworthiness of loan applicants.", requirements="Credit analysis, financial statements, banking", job_type="Full-time", category="Finance", is_remote=False),
            Job(title="Supply Chain Manager", company="Retail Giant", location="Bentonville, AR", salary_min=85000, salary_max=115000, description="Manage supply chain operations.", requirements="Supply chain management, logistics, ERP systems", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Compliance Officer", company="Financial Services", location="New York, NY", salary_min=80000, salary_max=110000, description="Ensure regulatory compliance.", requirements="Compliance knowledge, regulations, auditing", job_type="Full-time", category="Finance", is_remote=False),
            
            # Healthcare & Sciences (10 jobs)
            Job(title="Registered Nurse", company="City Hospital", location="Los Angeles, CA", salary_min=70000, salary_max=95000, description="Provide patient care and support.", requirements="RN license, BSN, clinical experience", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Pharmacist", company="Pharmacy Chain", location="Phoenix, AZ", salary_min=110000, salary_max=140000, description="Dispense medications and provide consultation.", requirements="PharmD, state license, patient care", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Medical Laboratory Technician", company="LabCorp", location="Burlington, NC", salary_min=45000, salary_max=60000, description="Conduct laboratory tests and analysis.", requirements="MLT certification, lab experience", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Physical Therapist", company="Rehab Center", location="Denver, CO", salary_min=75000, salary_max=95000, description="Provide physical therapy services.", requirements="DPT, state license, patient care", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Research Scientist", company="Biotech Labs", location="San Diego, CA", salary_min=85000, salary_max=120000, description="Conduct scientific research and experiments.", requirements="PhD in life sciences, research experience", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Clinical Research Coordinator", company="Pharma Inc", location="Boston, MA", salary_min=55000, salary_max=75000, description="Coordinate clinical trials and research.", requirements="Clinical research, GCP, regulatory knowledge", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Medical Writer", company="HealthComm", location="Remote", salary_min=70000, salary_max=95000, description="Write medical and scientific content.", requirements="Life sciences degree, medical writing", job_type="Full-time", category="Other", is_remote=True),
            Job(title="Radiologic Technologist", company="Imaging Center", location="Houston, TX", salary_min=55000, salary_max=75000, description="Perform diagnostic imaging procedures.", requirements="ARRT certification, radiology experience", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Bioinformatics Specialist", company="Genomics Lab", location="San Francisco, CA", salary_min=90000, salary_max=125000, description="Analyze biological data using computational methods.", requirements="Bioinformatics, Python/R, genomics", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Occupational Therapist", company="Healthcare Services", location="Seattle, WA", salary_min=70000, salary_max=90000, description="Help patients develop daily living skills.", requirements="OT license, patient assessment", job_type="Full-time", category="Other", is_remote=False),
            
            # Education & Other (10 jobs)
            Job(title="Software Training Instructor", company="Tech Academy", location="Remote", salary_min=55000, salary_max=80000, description="Teach programming courses online.", requirements="Software development, teaching experience", job_type="Full-time", category="Other", is_remote=True),
            Job(title="HR Manager", company="PeopleFirst Inc", location="Dallas, TX", salary_min=70000, salary_max=95000, description="Manage recruitment and employee relations.", requirements="HR experience, SHRM certification", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Project Manager", company="Construction Plus", location="Phoenix, AZ", salary_min=80000, salary_max=110000, description="Manage construction projects from start to finish.", requirements="PMP certification, 5+ years experience", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Customer Success Manager", company="SaaS Company", location="Remote", salary_min=65000, salary_max=90000, description="Ensure customer satisfaction and drive product adoption.", requirements="3+ years customer success experience", job_type="Full-time", category="Other", is_remote=True),
            Job(title="Legal Assistant", company="Law Firm", location="New York, NY", salary_min=50000, salary_max=70000, description="Support attorneys with legal research and documentation.", requirements="Paralegal certificate, legal research", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Executive Assistant", company="Corporate HQ", location="San Francisco, CA", salary_min=60000, salary_max=85000, description="Provide administrative support to executives.", requirements="Executive support, organization, communication", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Translator", company="Language Services", location="Remote", salary_min=45000, salary_max=65000, description="Translate documents and communications.", requirements="Bilingual, translation certification", job_type="Contract", category="Other", is_remote=True),
            Job(title="Urban Planner", company="City Planning Dept", location="Portland, OR", salary_min=65000, salary_max=90000, description="Plan land use and community development.", requirements="Urban planning degree, GIS, zoning knowledge", job_type="Full-time", category="Other", is_remote=False),
            Job(title="Real Estate Agent", company="Realty Group", location="Miami, FL", salary_min=50000, salary_max=100000, description="Help clients buy and sell properties.", requirements="Real estate license, sales experience", job_type="Commission", category="Other", is_remote=False),
            Job(title="Interior Designer", company="Design Interiors", location="New York, NY", salary_min=55000, salary_max=85000, description="Design interior spaces for residential and commercial clients.", requirements="Design degree, CAD, portfolio", job_type="Full-time", category="Other", is_remote=False),
        ]
        db.add_all(sample_jobs)
        db.commit()
        jobs = db.query(Job).all()
    
    return jobs

@app.get("/jobs/recommended")
async def get_recommended_jobs(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get job recommendations based on user's major/field of study"""
    user_major = current_user.graduation_institution.lower() if current_user.graduation_institution else ""
    print(f"User major from graduation_institution: '{user_major}'")
    
    # Define major to category/title keywords mapping
    major_keywords = {
        'computer science': ['developer', 'software', 'programmer', 'engineer', 'it', 'tech', 'data', 'web'],
        'information technology': ['it', 'developer', 'software', 'tech', 'system', 'network'],
        'software engineering': ['software', 'developer', 'engineer', 'programmer', 'tech'],
        'computer engineering': ['engineer', 'software', 'hardware', 'developer', 'tech'],
        'data science': ['data', 'analyst', 'scientist', 'analytics', 'bi', 'machine learning'],
        'artificial intelligence': ['ai', 'machine learning', 'data', 'scientist', 'ml'],
        'cybersecurity': ['security', 'cybersecurity', 'analyst', 'engineer'],
        'business administration': ['manager', 'business', 'admin', 'operations', 'consultant'],
        'management': ['manager', 'director', 'operations', 'project', 'business'],
        'marketing': ['marketing', 'digital', 'social media', 'brand', 'content'],
        'finance': ['financial', 'analyst', 'accountant', 'finance', 'banking'],
        'accounting': ['accountant', 'finance', 'auditor', 'tax'],
        'economics': ['economist', 'analyst', 'financial', 'research'],
        'mechanical engineering': ['mechanical', 'engineer', 'manufacturing', 'design'],
        'electrical engineering': ['electrical', 'engineer', 'electronics', 'power'],
        'civil engineering': ['civil', 'engineer', 'construction', 'infrastructure'],
        'chemical engineering': ['chemical', 'engineer', 'process', 'manufacturing'],
        'nursing': ['nurse', 'healthcare', 'medical', 'clinical'],
        'medicine': ['doctor', 'physician', 'medical', 'clinical', 'healthcare'],
        'pharmacy': ['pharmacist', 'pharmaceutical', 'clinical'],
    }
    
    # Get keywords for user's major
    keywords = []
    for major, related_keywords in major_keywords.items():
        if major in user_major:
            keywords = related_keywords
            break
    
    print(f"Matched keywords: {keywords}")
    
    # If no specific keywords found, use general job search
    if not keywords:
        jobs = db.query(Job).limit(10).all()
        print(f"No keywords matched, returning {len(jobs)} general jobs")
    else:
        # Search for jobs matching keywords in title or category
        query = db.query(Job)
        filters = []
        for keyword in keywords:
            filters.append(Job.title.ilike(f'%{keyword}%'))
            filters.append(Job.category.ilike(f'%{keyword}%'))
        
        from sqlalchemy import or_
        query = query.filter(or_(*filters))
        jobs = query.limit(20).all()
        print(f"Found {len(jobs)} jobs matching keywords")
        
        # If no matches, return general jobs
        if not jobs:
            jobs = db.query(Job).limit(10).all()
            print(f"No keyword matches, returning {len(jobs)} general jobs")
    
    return jobs

@app.post("/jobs/")
async def create_job(job: JobCreate, db: Session = Depends(get_db)):
    db_job = Job(**job.dict())
    db.add(db_job)
    db.commit()
    db.refresh(db_job)
    return db_job

@app.post("/applications/")
async def create_application(
    application: ApplicationCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Check if already applied
    existing = db.query(JobApplication).filter(
        JobApplication.user_id == current_user.id,
        JobApplication.job_id == application.job_id
    ).first()
    
    if existing:
        raise HTTPException(status_code=400, detail="Already applied")
    
    # Get job details for email
    job = db.query(Job).filter(Job.id == application.job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    # Create application
    db_application = JobApplication(
        user_id=current_user.id,
        job_id=application.job_id,
        status="pending"
    )
    
    db.add(db_application)
    db.commit()
    
    # Send confirmation email
    EmailService.send_application_confirmation(
        current_user.email,
        job.title,
        job.company
    )
    
    return {"message": "Application submitted successfully", "application_id": db_application.id}

@app.get("/applications/")
async def get_applications(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Get applications for the authenticated user only
    applications = db.query(JobApplication).filter(
        JobApplication.user_id == current_user.id
    ).all()
    
    # Get job details for each application
    result = []
    for app in applications:
        job = db.query(Job).filter(Job.id == app.job_id).first()
        if job:
            result.append({
                "id": app.id,
                "job_title": job.title,
                "company": job.company,
                "applied_at": app.applied_at,
                "status": app.status
            })
    
    return result

@app.get("/")
async def root():
    return {"message": "Job Search API is running. Use /docs for API documentation."}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8080)